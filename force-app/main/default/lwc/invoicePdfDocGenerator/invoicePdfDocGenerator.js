import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getPreviewUrl from '@salesforce/apex/InvoicePdfService.getPreviewUrl';
import getInvoiceMessage from '@salesforce/apex/InvoicePdfService.getInvoiceMessage';
import sendInvoice from '@salesforce/apex/InvoicePdfService.sendInvoice';

export default class InvoicePdfDocGenerator extends LightningElement {

    @api recordId;
    previewUrl;
    message;
    showModal = false;

    @api async openPreview(invoiceId) {
        console.log('openPreview');
        this.recordId = invoiceId;
        this.previewUrl = await getPreviewUrl({ invoiceId });
        this.message = await getInvoiceMessage({ invoiceId });

        this.showModal = true;
    }

    handleCancel() {
        this.showModal = false;
    }

    async handleSend() {
        console.log('handleSend');
        // await sendInvoice({ invoiceId: this.recordId });
        // this.showModal = false;

        // this.dispatchEvent(new CustomEvent('sent'));

        try {
            await sendInvoice({ invoiceId: this.recordId });

            this.showModal = false;

            // SUCCESS TOAST
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: 'Invoice email sent successfully.',
                    variant: 'success'
                })
            );

            
            this.dispatchEvent(new CustomEvent('sent'));

        } catch (error) {
            // ERROR TOAST
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: error?.body?.message || 'Failed to send invoice.',
                    variant: 'error'
                })
            );
        }
    }
}