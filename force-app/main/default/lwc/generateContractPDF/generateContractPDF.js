import { LightningElement, api } from 'lwc';
export default class GenerateContractPDF extends LightningElement {
    siteURL;
    @api recordId;

    connectedCallback() {

        console.log('recordId: ' + this.recordId);
        
        this.siteURL = '/apex/RetainerPDFforLead?recId=' + this.recordId;

    }
}