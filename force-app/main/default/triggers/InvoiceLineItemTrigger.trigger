trigger InvoiceLineItemTrigger on Invoice_Line_Item__c (after insert) {
    if (Trigger.isAfter && Trigger.isInsert) {
        InvoiceLineItemAutoQBOHandler.handle(Trigger.new);
    }
}