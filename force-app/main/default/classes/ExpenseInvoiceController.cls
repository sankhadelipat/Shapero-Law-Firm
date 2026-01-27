public with sharing class ExpenseInvoiceController {

    /* =========================
       GET EXPENSES (UNCHANGED)
       ========================= */
    @AuraEnabled(cacheable=true)
    public static List<Expense__c> getExpenses(
        String dateFilter,
        Integer limitSize,
        Integer offsetSize,
        Date fromDate,
        Date toDate
    ) {
        String baseQuery =
            'SELECT Id, Expense_Date__c, Category__c, Invoiced__c, Amount__c, Description__c, ' +
            'Account__c, Account__r.Name ' +
            'FROM Expense__c ';

        String whereClause = '';

        if (dateFilter != null && dateFilter != 'CUSTOM') {
            whereClause = 'WHERE Expense_Date__c = ' + dateFilter;
        }

        if (dateFilter == 'CUSTOM' && fromDate != null && toDate != null) {
            whereClause =
                'WHERE Expense_Date__c >= :fromDate AND Expense_Date__c <= :toDate';
        }

        String finalQuery =
            baseQuery +
            whereClause +
            ' ORDER BY Expense_Date__c DESC ' +
            ' LIMIT :limitSize OFFSET :offsetSize';

        return Database.query(finalQuery);
    }

    /* ======================================
       ADD EXPENSES TO EXISTING INVOICE
       ====================================== */
    @AuraEnabled
    public static void addExpensesToExistingInvoice(List<Id> expenseIds) {
        try {
            if (expenseIds == null || expenseIds.isEmpty()) {
                throw new AuraHandledException('No expenses selected.');
            }

            /* ---------------------------
               Load Expenses
               --------------------------- */
            List<Expense__c> expenses = [
                SELECT Id, Invoiced__c, Account__c, Amount__c,
                       Description__c, Status__c
                FROM Expense__c
                WHERE Id IN :expenseIds
            ];

            Id accountId;

            for (Expense__c exp : expenses) {
                if (exp.Invoiced__c) {
                    throw new AuraHandledException(
                        'Some selected expenses are already invoiced.'
                    );
                }
                if (exp.Account__c == null) {
                    throw new AuraHandledException(
                        'All expenses must have an Account.'
                    );
                }

                if (accountId == null) {
                    accountId = exp.Account__c;
                } else if (accountId != exp.Account__c) {
                    throw new AuraHandledException(
                        'All selected expenses must belong to the same Account.'
                    );
                }
            }

            /* ---------------------------
               Find Existing Invoice
               --------------------------- */
            List<Invoice__c> invoices = [
                SELECT Id, Status__c, Account__c
                FROM Invoice__c
                WHERE Account__c = :accountId
                  AND Status__c IN ('Draft')
                ORDER BY CreatedDate ASC
                LIMIT 1
            ];

            if (invoices.isEmpty()) {
                throw new AuraHandledException(
                    'No Draft/Open invoice found for this Account.'
                );
            }

            Invoice__c invoice = invoices[0];

            /* ---------------------------
               Product for Line Items
               --------------------------- */
            Product2 product = [
                SELECT Id
                FROM Product2
                WHERE Name = 'Reimbursable Amount'
                LIMIT 1
            ];

            /* ---------------------------
               Create Invoice Line Items
               --------------------------- */
            List<Invoice_Line_Item__c> lineItems = new List<Invoice_Line_Item__c>();

            for (Expense__c exp : expenses) {
                lineItems.add(new Invoice_Line_Item__c(
                    Invoice__c        = invoice.Id,
                    Fee_Type__c       = product.Id,
                    Description__c    = exp.Description__c,
                    Quantity__c       = 1,
                    Unit_Price__c     = exp.Amount__c,
                    Tax_Percentage__c = 1
                ));

                exp.Invoiced__c = true;
                exp.Invoice__c  = invoice.Id;
                exp.Status__c   = 'Approved';
            }

            insert lineItems;
            update expenses;

            /* ---------------------------------
               NOTE:
               Your existing QBO sync logic
               (trigger / batch / future / queueable)
               will now auto-sync this invoice
               with new line items.
               --------------------------------- */

        } catch (Exception e) {
            throw new AuraHandledException(
                'Failed to add expenses to invoice: ' + e.getMessage()
            );
        }
    }

    /* =========================
       UPDATE EXPENSE ACCOUNT
       ========================= */
    @AuraEnabled
    public static void updateExpenseAccount(Id expenseId, Id accountId) {
        if (expenseId == null || accountId == null) {
            throw new AuraHandledException('Invalid input.');
        }

        update new Expense__c(
            Id = expenseId,
            Account__c = accountId
        );
    }
}