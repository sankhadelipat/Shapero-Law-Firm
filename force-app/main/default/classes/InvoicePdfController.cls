public class InvoicePdfController {

    public Invoice__c invoice { get; private set; }
    public List<Invoice_Line_Item__c> lineItems { get; private set; }
    //public List<Expense__c> expenses { get; private set; }
    public Account billingAccount { get; private set; }

    public InvoicePdfController(ApexPages.StandardController sc) {

        system.debug('--InvoicePdfController--');

        Id invoiceId = sc.getId();
        system.debug('--InvoicePdfController--' + invoiceId);
        
        // Invoice
        invoice = [
            SELECT Id, Name, Total_Amount__c, Invoice_Date__c, Due_Date__c,
                   Stripe_Payment_Link__c, Account__c
            FROM Invoice__c
            WHERE Id = :invoiceId
            LIMIT 1
        ];
        system.debug('pdf invoice: ' + invoice);
        
        ApexPages.currentPage().getHeaders().put(
            'Content-Disposition',
            'inline; filename='+ invoice.Name + '.pdf'
        );


        // Line Items
        lineItems = [
            SELECT Id, Name, Line_Amount__c, Unit_Price__c, Tax_Percentage__c,
                   Tax_Amount__c, Quantity__c, Description__c,
                   Fee_Type__c, Fee_Type__r.Name
            FROM Invoice_Line_Item__c
            WHERE Invoice__c = :invoice.Id
            ORDER BY Name
        ];
        system.debug('pdf lineItems: '+ lineItems);

        // Expenses
        /*expenses = [
            SELECT Id, Approval_Date__c, Description__c, Amount__c
            FROM Expense__c
            WHERE Invoice__c = :invoice.Id
        ];
        system.debug('pdf expenses: '+ expenses);*/

        // Billing Account (from Invoice → Account lookup)
        if (invoice.Account__c != null) {
            billingAccount = [
                SELECT Id, BillingStreet, BillingCity, BillingState,
                       BillingPostalCode, BillingCountry
                FROM Account
                WHERE Id = :invoice.Account__c
                LIMIT 1
            ];
        }
        system.debug('pdf billingAccount: '+ billingAccount);
    }
}