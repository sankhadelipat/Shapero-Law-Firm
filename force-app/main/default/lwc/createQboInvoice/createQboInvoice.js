import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import createInvoice from '@salesforce/apex/QuickBooksInvoiceService.createInvoice';
import { getRecord } from 'lightning/uiRecordApi';
import { getRelatedListRecords } from 'lightning/uiRelatedListApi';
import { refreshApex } from '@salesforce/apex';

const FIELDS = ['Invoice__c.QBO_Invoice_ID__c'];

export default class CreateQboInvoice extends LightningElement {
    @api recordId;

    isDisabled = false;
    hasLineItems = false;

    wiredInvoiceResult;
    wiredLinesResult;

tryAutoRun() {
    if (
        this.hasRun ||
        !this.invoiceLoaded ||
        !this.linesLoaded ||
        this.isDisabled
    ) {
        return;
    }

    this.hasRun = true;
    this.handleClick();
}



    /* Invoice record */
 @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
wiredInvoice(result) {
    this.wiredInvoiceResult = result;

    if (result.data) {
        const qboId = result.data.fields.QBO_Invoice_ID__c.value;
        this.isDisabled = !!qboId;
        this.invoiceLoaded = true;
        this.tryAutoRun();
    }
}

@wire(getRelatedListRecords, {
    parentRecordId: '$recordId',
    relatedListId: 'Invoice_Line_Items__r',
    fields: ['Invoice_Line_Item__c.Id']
})
wiredLines(result) {
    this.wiredLinesResult = result;

    if (result.data) {
        this.hasLineItems = result.data.records.length > 0;
        this.linesLoaded = true;
        this.tryAutoRun();
    }
}

    handleClick() {

        // ❌ No line items → stop here
        if (!this.hasLineItems) {
            this.showToast(
                'Error',
                'Invoice line items are not linked to this invoice',
                'error'
            );
            return;
        }

        createInvoice({ invoiceId: this.recordId })
            .then(() => {
                this.showToast(
                    'Success',
                    'Invoice successfully created in QuickBooks',
                    'success'
                );
                this.isDisabled = true;
                return refreshApex(this.wiredInvoiceResult);
            })
           .catch(error => {
    let message = 'Failed to create QBO Invoice';

    // Field-level validation errors
    if (error.body?.output?.fieldErrors) {
        const fieldErrors = error.body.output.fieldErrors;
        message = Object.keys(fieldErrors)
            .map(field =>
                fieldErrors[field].map(err => err.message).join(', ')
            )
            .join(' | ');
    }
    // General Apex errors
    else if (error.body?.message) {
        message = error.body.message;
    }

    this.showToast('Error', message, 'error');
});

    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }
}