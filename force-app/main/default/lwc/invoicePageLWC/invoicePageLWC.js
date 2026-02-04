import { LightningElement, api } from 'lwc';

export default class InvoicePageLWC extends LightningElement {
    @api recordId;  // invoice id passed from Flexipage

    handlePreview() {
        console.log('clicked handlePreview: ', this.recordId);
        const child = this.template.querySelector('c-invoice-pdf-doc-generator');
        child.openPreview(this.recordId);
    }

    handleChildSent() {
        console.log('Invoice email sent successfully.');
    }
}