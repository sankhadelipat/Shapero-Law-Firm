public class MonthlyInvoiceBatch implements Database.Batchable<SObject> {
    public Database.QueryLocator start(Database.BatchableContext bc) {
        Date today = Date.today();

        return Database.getQueryLocator(
            [
                SELECT
                    Id,
                    Name,
                    Start_Date__c,
                    End_Date__c,
                    Status__c,
                    Account__c,
                    Contract__c,
                    Contract__r.Contract_Type__c,
                    Contract__r.Monthly_Fee__c
                FROM Invoice__c
                WHERE Status__c = 'Draft' AND End_Date__c = :today AND Contract__r.Contract_Type__c = 'Retainer'
            ]
        );
    }

    public void execute(Database.BatchableContext bc, List<Invoice__c> scope) {
        if (scope.isEmpty()) {
            return;
        }

        // Update invoice status to 'Finalized'
        List<Invoice__c> finalizedInvoices = new List<Invoice__c>();

        for (Invoice__c invoice : scope) {
            invoice.Status__c = 'Finalized';
            finalizedInvoices.add(invoice);
        }
        update finalizedInvoices;

        /*// Load previous invoices
        Set<Id> priorInvoiceIds = new Set<Id>();

        for (Invoice__c invoice : finalizedInvoices) {
            if (invoice.Previous_Invoice__c != null) {
                priorInvoiceIds.add(invoice.Previous_Invoice__c);
            }
        }

        Map<Id, Invoice__c> priorInvoicesMap = new Map<Id, Invoice__c>();

        if (!priorInvoiceIds.isEmpty()) {
            priorInvoicesMap = new Map<Id, Invoice__c>(
                [
                    SELECT Id, Amount_Due__c, Status__c
                    FROM Invoice__c
                    WHERE Id IN :priorInvoiceIds
                ]
            );
        }

        // Create line items for previous due amounts
        List<Invoice_Line_Item__c> adjustmentLines = new List<Invoice_Line_Item__c>();
        Id previousDueProductId = ProductUtil.getProductId('Previous Month Due');

        for (Invoice__c invoice : finalizedInvoices) {
            if (invoice.Previous_Invoice__c == null)
                continue;

            Invoice__c priorInv = priorInvoicesMap.get(invoice.Previous_Invoice__c);
            if (priorInv == null)
                continue;
            if (priorInv.Amount_Due__c <= 0)
                continue;

            Invoice_Line_Item__c lineItem = new Invoice_Line_Item__c(
                Invoice__c = invoice.Id,
                Fee_Type__c = previousDueProductId,
                Description__c = 'Previous Month Due Adjustment',
                Quantity__c = 1,
                Unit_Price__c = priorInv.Amount_Due__c
            );
            adjustmentLines.add(lineItem);
        }
        if (!adjustmentLines.isEmpty()) {
            insert adjustmentLines;
        }*/

        // Create next month's invoice
        List<Invoice__c> nextInvoicesToCreate = new List<Invoice__c>();
        Map<Id, Invoice__c> currentToNextMap = new Map<Id, Invoice__c>();

        for (Invoice__c invoice : finalizedInvoices) {
            if (invoice.Start_Date__c == null || invoice.End_Date__c == null)
                continue;
            Date nextStart = invoice.End_Date__c.addDays(1);
            Date nextEnd = nextStart.addMonths(1).addDays(-1);

            Invoice__c nextInv = new Invoice__c(
                Account__c = invoice.Account__c,
                Contract__c = invoice.Contract__c,
                Previous_Invoice__c = invoice.Id,
                Start_Date__c = nextStart,
                End_Date__c = nextEnd,
                Status__c = 'Draft'
            );
            nextInvoicesToCreate.add(nextInv);
            currentToNextMap.put(invoice.Id, nextInv);
        }
        insert nextInvoicesToCreate;

        // Create line items for retainer
        List<Invoice_Line_Item__c> retainerLines = new List<Invoice_Line_Item__c>();
        Id retainerProductId = ProductUtil.getProductId('Monthly Retainer');

        for (Invoice__c invoice : finalizedInvoices) {
            if (invoice.Contract__r.Contract_Type__c != 'Retainer')
                continue;

            Invoice__c nextInv = currentToNextMap.get(invoice.Id);
            if (nextInv == null)
                continue;

            Invoice_Line_Item__c lineItem = new Invoice_Line_Item__c(
                Invoice__c = nextInv.Id,
                Fee_Type__c = retainerProductId,
                Description__c = 'Monthly Retainer Fee',
                Quantity__c = 1,
                Unit_Price__c = invoice.Contract__r.Monthly_Fee__c
            );
            retainerLines.add(lineItem);
        }
        if (!retainerLines.isEmpty()) {
            insert retainerLines;
        }
    }

    public void finish(Database.BatchableContext bc) {
        // No post-processing needed
    }
}