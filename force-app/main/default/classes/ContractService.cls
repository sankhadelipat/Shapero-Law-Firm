public class ContractService {
    public static void generateInitialRetainerInvoices(Set<Id> contractIds) {
        if (contractIds == null || contractIds.isEmpty())
            return;

        // Load contracts
        List<Contract> contracts = [
            SELECT Id, AccountId, StartDate, Monthly_Fee__c
            FROM Contract
            WHERE Id IN :contractIds
        ];

        // Get monthly retainer product Id
        Id retainerProductId = ProductUtil.getProductId('Monthly Retainer');

        // -----------------------------
        // 1. CREATE FIRST MONTH INVOICES
        // -----------------------------
        List<Invoice__c> invoicesToInsert = new List<Invoice__c>();

        for (Contract con : contracts) {
            Date startDate = con.StartDate;
            Date firstDayOfMonth = Date.newInstance(startDate.year(), startDate.month(), 1);
            Date lastDayOfMonth = firstDayOfMonth.addMonths(1).addDays(-1);

            Invoice__c inv = new Invoice__c(
                Account__c = con.AccountId,
                Contract__c = con.Id,
                Start_Date__c = startDate,
                End_Date__c = lastDayOfMonth,
                Invoice_Date__c = startDate,
                Due_Date__c = lastDayOfMonth.addDays(7),
                Status__c = 'Draft'
            );

            invoicesToInsert.add(inv);
        }
        insert invoicesToInsert;

        // --------------------------------
        // 2. CREATE PRORATED LINE ITEMS
        // --------------------------------
        List<Invoice_Line_Item__c> lineItemsToInsert = new List<Invoice_Line_Item__c>();

        for (Invoice__c inv : invoicesToInsert) {
            Map<Id, Contract> contractsMap = new Map<Id, Contract>(contracts);
            Contract con = contractsMap.get(inv.Contract__c);

            Date startDate = inv.Start_Date__c;
            Date endDate = inv.End_Date__c;
            // Integer daysInMonth = endDate.day();
            Integer daysInMonth = Date.daysInMonth(startDate.year(), startDate.month());
            Integer billableDays = startDate.daysBetween(endDate) + 1;
            Decimal perDayRate = con.Monthly_Fee__c / daysInMonth;
            Decimal proratedAmount = (perDayRate * billableDays).setScale(2);

            Invoice_Line_Item__c lineItem = new Invoice_Line_Item__c(
                Invoice__c = inv.Id,
                Fee_Type__c = retainerProductId,
                Description__c = 'Monthly Retainer Fee',
                Quantity__c = 1,
                Unit_Price__c = proratedAmount
            );
            lineItemsToInsert.add(lineItem);
        }
        insert lineItemsToInsert;
    }
}