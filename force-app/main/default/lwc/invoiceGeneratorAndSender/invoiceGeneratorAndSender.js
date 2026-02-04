import { LightningElement , api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';

import getPreviewUrl from '@salesforce/apex/InvoicePdfService.getPreviewUrl';
import getInvoiceMessage from '@salesforce/apex/InvoicePdfService.getInvoiceMessage';
import sendInvoice from '@salesforce/apex/InvoicePdfService.sendInvoice';

export default class InvoiceGeneratorAndSender extends LightningElement {

    // @api recordId;
    // recordId = 'a0Bdh000004CIzlEAG';

    _recordId;
    hasInitialized = false;

    @api
    set recordId(value) {
        this._recordId = value;
        console.log('Record Id received:', value);

        if (!this.hasInitialized) {
            this.hasInitialized = true;
            this.initialize();
        }
    }

    get recordId() {
        return this._recordId;
    }

    previewUrl;
    message;

    // async connectedCallback() {
    async initialize() {
        console.log('recordId: ', this.recordId);
        try {
            this.previewUrl = await getPreviewUrl({ invoiceId: this.recordId });
            this.message = await getInvoiceMessage({ invoiceId: this.recordId });
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: 'Failed to load invoice preview.',
                    variant: 'error'
                })
            );
            this.closeAction();
        }
    }

    handleCancel() {
        this.closeAction();
    }

    async handleSend() {
        try {
            await sendInvoice({ invoiceId: this.recordId });

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: 'Invoice email sent successfully.',
                    variant: 'success'
                })
            );

            this.closeAction();

        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: error?.body?.message || 'Failed to send invoice.',
                    variant: 'error'
                })
            );
        }
    }

    closeAction() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }


}