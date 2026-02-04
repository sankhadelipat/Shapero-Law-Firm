public with sharing class InvoiceLineItemAutoQBOHandler {

    public static void handle(
        List<Invoice_Line_Item__c> newList,
        Map<Id, Invoice_Line_Item__c> oldMap
    ) {
        Set<Id> invoiceIds = new Set<Id>();

        Boolean isUpdate = (oldMap != null);

        for (Invoice_Line_Item__c li : newList) {
            if (li.Invoice__c != null)
                invoiceIds.add(li.Invoice__c);
        }

        if (isUpdate) {
            for (Invoice_Line_Item__c oldLi : oldMap.values()) {
                if (oldLi.Invoice__c != null)
                    invoiceIds.add(oldLi.Invoice__c);
            }
        }

        if (!invoiceIds.isEmpty()) {
            // 🔥 FORCE UPDATE ON LINE ITEM CHANGE
            QuickBooksInvoiceService.createInvoiceAuto(
                invoiceIds,
                isUpdate
            );
        }
    }
}