public class QuickBooksCustomerService {

    @future(callout=true)
    public static void createCustomers(List<Id> accountIds) {
        
        String realmId = QuickBooks_Config__mdt.getInstance('Default').Realm_Id__c;

        List<Account> accounts = [
            SELECT Id, FirstName,LastName,Name,PersonEmail,Phone,BillingStreet,
            BillingCity,BillingPostalCode,BillingState,BillingCountry,QBO_Customer_ID__c
            FROM Account
            WHERE Id IN :accountIds
        ];

        Http http = new Http();
        List<Account> accountsToUpdate = new List<Account>();

        for (Account acc : accounts) {

            if (!String.isBlank(acc.QBO_Customer_ID__c)) {
                continue;
            }

            HttpRequest req = new HttpRequest();
            req.setMethod('POST');
            req.setEndpoint(
                'callout:QBO_Named_Credential/v3/company/' +
                realmId + '/customer'
            );

            req.setHeader('Content-Type', 'application/json');
            req.setHeader('Accept', 'application/json');

            Map<String, Object> body = new Map<String, Object>();
            body.put('DisplayName', acc.Name);
            body.put('GivenName', acc.FirstName);
            body.put('FamilyName', acc.LastName);
            body.put(
                'PrimaryEmailAddr',
                new Map<String, Object>{
                    'Address' => acc.PersonEmail
                }
            );
            body.put(
                'PrimaryPhone',
                new Map<String, Object>{
                    'FreeFormNumber' => acc.Phone
                }
            );

            body.put(
                'BillAddr',
                new Map<String, Object>{
                    'Line1' => acc.BillingStreet,
                    'City' => acc.BillingCity,
                    'PostalCode' => acc.BillingPostalCode,
                    'CountrySubDivisionCode' => acc.BillingState,
                    'Country' => acc.BillingCountry
                });
            req.setBody(JSON.serialize(body));

            try {
                HttpResponse res = http.send(req);

                if (res.getStatusCode() == 200 || res.getStatusCode() == 201) {
                    Map<String, Object> resp =(Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                    Map<String, Object> customer =(Map<String, Object>) resp.get('Customer');
                    
                    accountsToUpdate.add(new Account(
                        Id = acc.Id,
                        QBO_Customer_ID__c = (String) customer.get('Id')
                    ));
                } else {
                    System.debug('QBO Error: ' + res.getBody());
                }
            } catch (CalloutException e) {
                System.debug('HTTP Callout Error: ' + e.getMessage());
            }
        }

        if (!accountsToUpdate.isEmpty()) {
            update accountsToUpdate;
        }
    }
}