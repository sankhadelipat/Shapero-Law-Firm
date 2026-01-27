public with sharing class InvoiceLineItemController {

    @AuraEnabled
    public static Id createInvoiceWithLines(Id accountId,Date invoiceDate,Date dueDate,List<InvoiceLineItemWrapper> lineItems) {
        if (lineItems == null || lineItems.isEmpty()) {
            throw new AuraHandledException('At least one line item is required');
        }

        Invoice__c inv = new Invoice__c(
            Account__c = accountId,
            Invoice_Date__c = invoiceDate,
            Due_Date__c = dueDate,
            Status__c = 'Draft'
        );
        insert inv;

        List<Invoice_Line_Item__c> itemsToInsert = new List<Invoice_Line_Item__c>();

        for (InvoiceLineItemWrapper w : lineItems) {
            itemsToInsert.add(new Invoice_Line_Item__c(
                Invoice__c = inv.Id,
                Fee_Type__c = w.productId,
                Description__c = w.description,
                Quantity__c = w.quantity,
                Unit_Price__c = w.amount,
                Tax_Percentage__c = w.taxPercentage
            ));
        }

        insert itemsToInsert;
     
        System.debug('Invoice Line Items inserted => ' + itemsToInsert);
        return inv.Id;
    }

    public class InvoiceLineItemWrapper {
    @AuraEnabled public Id productId { get; set; }
    @AuraEnabled public String description { get; set; }
    @AuraEnabled public Decimal quantity { get; set; }
    @AuraEnabled public Decimal amount { get; set; }
    @AuraEnabled public Decimal taxPercentage { get; set; }
}

}