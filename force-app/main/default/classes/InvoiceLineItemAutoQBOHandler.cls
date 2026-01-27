public with sharing class InvoiceLineItemAutoQBOHandler {

    public static void handle(List<Invoice_Line_Item__c> newLines) {

        /* --------------------------------
           Collect Invoice Ids
           -------------------------------- */
        Set<Id> invoiceIds = new Set<Id>();

        for (Invoice_Line_Item__c li : newLines) {
            if (li.Invoice__c != null) {
                invoiceIds.add(li.Invoice__c);
            }
        }

        if (invoiceIds.isEmpty()) return;

        /* --------------------------------
           Check if invoice has expenses
           (Expense → Invoice relationship)
           -------------------------------- */
        Map<Id, Integer> expenseCountMap = new Map<Id, Integer>();

        for (AggregateResult ar : [
            SELECT Invoice__c invoiceId, COUNT(Id) cnt
            FROM Expense__c
            WHERE Invoice__c IN :invoiceIds
            GROUP BY Invoice__c
        ]) {
            expenseCountMap.put(
                (Id) ar.get('invoiceId'),
                (Integer) ar.get('cnt')
            );
        }

        /* --------------------------------
           Load invoices
           -------------------------------- */
        List<Invoice__c> invoices = [
            SELECT Id, Status__c, QBO_Invoice_ID__c
            FROM Invoice__c
            WHERE Id IN :invoiceIds
        ];

        Set<Id> eligibleInvoiceIds = new Set<Id>();

        for (Invoice__c inv : invoices) {

            // ✅ Draft
            // ✅ Not synced
            // ✅ Has expenses linked
            if (inv.Status__c == 'Draft'
                && String.isBlank(inv.QBO_Invoice_ID__c)
                && expenseCountMap.containsKey(inv.Id)) {

                eligibleInvoiceIds.add(inv.Id);
            }
        }

        if (eligibleInvoiceIds.isEmpty()) return;

        /* --------------------------------
           AUTO CREATE QBO INVOICE
           Using your EXISTING class
           -------------------------------- */
        for (Id invId : eligibleInvoiceIds) {
            QuickBooksInvoiceService.createInvoice(invId);
        }
    }
}