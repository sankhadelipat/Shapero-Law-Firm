import { LightningElement, api, track } from 'lwc';
import createInvoiceWithLines from '@salesforce/apex/InvoiceLineItemController.createInvoiceWithLines';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class CreateInvoiceLineItem extends LightningElement {

    @api recordId;

    @track showModal = false;
    invoiceDate;
    dueDate;

    @track lineItems = [
        { key: Date.now(), productId: null, description: '', amount: null }
    ];

    connectedCallback() {
        this.invoiceDate = new Date().toISOString().split('T')[0];
    }

    openModal() {
        this.showModal = true;
    }

    closeModal() {
        this.showModal = false;
    }

    handleDueDateChange(event) {
        this.dueDate = event.target.value;
    }

    addRow() {
        this.lineItems = [
            ...this.lineItems,
            {
                key: Date.now() + Math.random(),
                productId: null,
                description: '',
                amount: null
            }
        ];
    }

    removeRow(event) {
        const index = event.target.dataset.index;
        this.lineItems.splice(index, 1);
        this.lineItems = [...this.lineItems];
    }

 handleRowChange(event) {
    const index = event.target.dataset.index;
    const field = event.target.dataset.field;

    let value = event.detail.value; // ✅ FIX

    if (field === 'amount') {
        value = value !== '' ? parseFloat(value) : null;
    }

    this.lineItems[index][field] = value;
}


handleProductChange(event) {
    const index = event.target.dataset.index;
    this.lineItems[index].productId = event.detail.recordId;
}




    submitForm() {
        if (!this.dueDate) {
            this.showToast('Error', 'Please select Due Date', 'error');
            return;
        }
    console.log(JSON.stringify(this.lineItems));

        const validLines = this.lineItems
           .filter(i => i.productId && i.amount !== null)
            .map(i => ({
                productId: i.productId,
                description: i.description,
                quantity: 1,
                amount: i.amount,
                taxPercentage: 0
            }));

        if (validLines.length === 0) {
            this.showToast('Error', 'Add at least one valid line item', 'error');
            return;
        }

        createInvoiceWithLines({
            accountId: this.recordId,
            invoiceDate: this.invoiceDate,
            dueDate: this.dueDate,
            lineItems: validLines
        })
        .then(() => {
            this.showToast('Success', 'Invoice created successfully', 'success');
            this.closeModal();
        })
        .catch(error => {
            this.showToast(
                'Error',
                error?.body?.message || 'Unexpected error',
                'error'
            );
        });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({ title, message, variant })
        );
    }
}