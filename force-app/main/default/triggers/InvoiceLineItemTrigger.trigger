trigger InvoiceLineItemTrigger on Invoice_Line_Item__c (after insert, after update) {
   InvoiceLineItemAutoQBOHandler.handle(Trigger.new,Trigger.isUpdate ? Trigger.oldMap : null);
}