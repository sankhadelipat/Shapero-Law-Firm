import { LightningElement, track } from 'lwc';
import getExpenses from '@salesforce/apex/ExpenseInvoiceController.getExpenses';
import addExpensesToExistingInvoice from '@salesforce/apex/ExpenseInvoiceController.addExpensesToExistingInvoice';
import updateExpenseAccount from '@salesforce/apex/ExpenseInvoiceController.updateExpenseAccount';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';


export default class GenerateInvoice extends LightningElement {

    @track expenses = [];
    allExpenses = [];


    selectedExpenses = [];
    isAllSelected = false;
    showReviewModal = false;

    /* ================= FILTERS ================= */

    dateFilter = 'All';
    statusFilter = 'All';

    fromDate;
    toDate;

    limitSize = 10;
    offsetSize = 0;
    currentPage = 1;


    /* ================= OPTIONS ================= */
    dateOptions = [
        { label: 'All', value: 'All' },
        { label: 'Today', value: 'TODAY' },
        { label: 'Yesterday', value: 'YESTERDAY' },
        { label: 'This Week', value: 'THIS_WEEK' },
        { label: 'Last Week', value: 'LAST_WEEK' },
        { label: 'This Month', value: 'THIS_MONTH' },
        { label: 'Last Month', value: 'LAST_MONTH' },
        { label: 'This Year', value: 'THIS_YEAR' }
    ];

    statusOptions = [
        { label: 'All', value: 'All' },
        { label: 'Pending', value: 'Pending' },
        { label: 'Invoiced', value: 'Invoiced' }
    ];

    /* ================= LIFECYCLE ================= */

    connectedCallback() {
        this.loadExpenses();
    }

/* ================= LOAD ================= */

loadExpenses() {
    getExpenses({
        dateFilter: this.dateFilter === 'All' ? null : this.dateFilter,
        limitSize: this.limitSize,
        offsetSize: this.offsetSize,
        fromDate: this.dateFilter === 'All' ? null : this.fromDate,
        toDate: this.dateFilter === 'All' ? null : this.toDate
    })
    .then(result => {
        const mapped = result.map(r => ({
            ...r,
            isDirty: false,
            selected: false,
            rowClass: r.Invoiced__c ? 'invoiced-row' : ''
        }));

        this.allExpenses = mapped;
        this.expenses = mapped;
    })
    .catch(error => {
        console.error(error);
    });
}



    /* ================= STATUS FILTER ================= */

    handleStatusChange(event) {
        this.statusFilter = event.detail.value;
        this.applyStatusFilter();
    }

    applyStatusFilter() {
        let data = [...this.allExpenses];

        if (this.statusFilter === 'Invoiced') {
            data = data.filter(e => e.Invoiced__c);
        } else if (this.statusFilter === 'Pending') {
            data = data.filter(e => !e.Invoiced__c);
        }

        this.expenses = data;
        this.updateHeaderCheckbox();
    }

    /* ================= DATE FILTER ================= */

    handleDateChange(event) {
        this.dateFilter = event.detail.value;
        this.currentPage = 1;
        this.offsetSize = 0;
        this.loadExpenses();
    }

    /* ================= ROW SELECT ================= */

    handleSelect(event) {
        const id = event.target.dataset.id;
        const checked = event.target.checked;

        this.expenses = this.expenses.map(exp => {
            if (exp.Id === id) {
                if (exp.Invoiced__c) return exp; // 🚫 block
                return { ...exp, selected: checked };
            }
            return exp;
        });

        this.syncToAll();
        this.updateHeaderCheckbox();
    }

    /* ================= SELECT ALL ================= */

    handleSelectAll(event) {
        const checked = event.target.checked;

        this.expenses = this.expenses.map(exp => {
            if (exp.Invoiced__c) {
                return { ...exp, selected: false }; // 🚫 never select invoiced
            }
            return { ...exp, selected: checked };
        });

        this.syncToAll();
        this.updateHeaderCheckbox();
    }

    get disableSelectAll() {
        return this.expenses.filter(e => !e.Invoiced__c).length === 0;
    }

    updateHeaderCheckbox() {
        const selectable = this.expenses.filter(e => !e.Invoiced__c);
        this.isAllSelected =
            selectable.length > 0 &&
            selectable.every(e => e.selected);
    }

    syncToAll() {
        const map = new Map(this.expenses.map(e => [e.Id, e.selected]));
        this.allExpenses = this.allExpenses.map(e =>
            map.has(e.Id) ? { ...e, selected: map.get(e.Id) } : e
        );
    }

    /* ================= ACCOUNT UPDATE ================= */

    handleAccountChange(event) {
        const id = event.currentTarget.dataset.id;
        const accountId = event.detail.recordId;
        const accountName = event.detail.recordName;

        this.expenses = this.expenses.map(exp =>
            exp.Id === id
                ? {
                    ...exp,
                    Account__c: accountId,
                    Account__r: { Name: accountName },
                    isDirty: true
                }
                : exp
        );
    }

   handleSave(event) {
    const expenseId = event.target.dataset.id;
    const expense = this.expenses.find(e => e.Id === expenseId);

    if (!expense || !expense.Account__c) return;

    updateExpenseAccount({
        expenseId: expense.Id,
        accountId: expense.Account__c
    })
    .then(() => {
        this.toast('Success', 'Account updated successfully', 'success');

        this.expenses = this.expenses.map(e =>
            e.Id === expenseId
                ? {
                    ...e,
                    isDirty: false,
                    Account__r: { Name: expense.Account__r.Name } // ✅ KEEP UPDATED
                }
                : e
        );
    })
    .catch(error => {
        this.toast(
            'Error',
            error?.body?.message || 'Failed to update Account',
            'error'
        );
    });
}


    /* ================= REVIEW & SUBMIT ================= */

   review() {
    this.selectedExpenses = this.expenses
        .filter(e => e.selected)
        .map(e => ({
            ...e,
            accountName: e.Account__r?.Name || '' // ✅ ALWAYS LATEST
        }));

    if (!this.selectedExpenses.length) {
        this.toast('Error', 'Select at least one expense', 'error');
        return;
    }

    this.showReviewModal = true;
}

      closeReviewModal() {
        this.showReviewModal = false;
    }

  submit() {
    const ids = this.selectedExpenses.map(e => e.Id);

    addExpensesToExistingInvoice({ expenseIds: ids })
        .then(() => {
            this.toast(
                'Success',
                'Expenses added with Invoice Line Item to existing invoice successfully',
                'success'
            );
            this.showReviewModal = false;
            this.loadExpenses();
        })
        .catch(error => {
            this.toast(
                'Error',
                error?.body?.message || 'Something went wrong',
                'error'
            );
        });
}


    /* ================= UTIL ================= */

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}