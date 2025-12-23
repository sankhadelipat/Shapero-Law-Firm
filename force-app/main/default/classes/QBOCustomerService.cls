public with sharing class QBOCustomerService {

    @InvocableMethod(
        label='Sync Account to QBO'
        description='Sync Salesforce Account to QuickBooks Online'
    )
    public static List<FlowResponse> syncAccountToQBO(List<FlowRequest> requests) {

        System.debug('=== QBOCustomerService START ===');
        System.debug('Incoming Requests: ' + requests);

        List<FlowResponse> responses = new List<FlowResponse>();

        for (FlowRequest reqItem : requests) {

            FlowResponse resp = new FlowResponse();

            System.debug('--- Processing Account Id: ' + reqItem.accountId);

            Account acc = [
                SELECT Id, Name, Phone,
                       BillingStreet, BillingCity, BillingState, BillingPostalCode,
                       Assigned_Attorney__c,
                       Billing_Status__c,
                       Payment_Method_On_File__c,
                       QBO_Customer_ID__c
                FROM Account
                WHERE Id = :reqItem.accountId
                LIMIT 1
            ];

            System.debug('Fetched Account: ' + acc);

            // Prevent duplicate sync
            if (acc.QBO_Customer_ID__c != null) {
                System.debug('Account already synced. QBO ID: ' + acc.QBO_Customer_ID__c);
                resp.message = 'Already Synced with QBO';
                responses.add(resp);
                continue;
            }

            // Build QBO payload
            Map<String, Object> customer = new Map<String, Object>{
                'DisplayName' => acc.Name,
                'Active' => acc.Billing_Status__c == 'Active',
                'Notes' => 'Assigned Attorney: ' + acc.Assigned_Attorney__c +
                           ', Payment Method: ' + acc.Payment_Method_On_File__c
            };

            if (acc.Phone != null) {
                customer.put(
                    'PrimaryPhone',
                    new Map<String, Object>{ 'FreeFormNumber' => acc.Phone }
                );
            }

            if (acc.BillingStreet != null) {
                customer.put(
                    'BillAddr',
                    new Map<String, Object>{
                        'Line1' => acc.BillingStreet,
                        'City' => acc.BillingCity,
                        'CountrySubDivisionCode' => acc.BillingState,
                        'PostalCode' => acc.BillingPostalCode
                    }
                );
            }

            System.debug('QBO Customer Payload: ' + JSON.serialize(customer));

            String realmId = '9341453864660341';
            System.debug('Using Realm ID: ' + realmId);

            HttpRequest httpReq = new HttpRequest();
            httpReq.setEndpoint(
                'callout:QBO_Named_Credential/v3/company/' + realmId + '/customer'
            );
            httpReq.setMethod('POST');
            httpReq.setHeader('Content-Type', 'application/json');
            httpReq.setBody(JSON.serialize(customer));

            System.debug('HTTP Request Endpoint: ' + httpReq.getEndpoint());
            System.debug('HTTP Request Body: ' + httpReq.getBody());

            Http http = new Http();
            HttpResponse res;

            try {
                res = http.send(httpReq);
            } catch (Exception ex) {
                System.debug('HTTP Callout Exception: ' + ex.getMessage());
                resp.message = 'HTTP Callout Failed: ' + ex.getMessage();
                responses.add(resp);
                continue;
            }

            System.debug('HTTP Status Code: ' + res.getStatusCode());
            System.debug('HTTP Response Body: ' + res.getBody());

            // Success
            if (res.getStatusCode() == 200 || res.getStatusCode() == 201) {

                Map<String, Object> responseMap =
                    (Map<String, Object>) JSON.deserializeUntyped(res.getBody());

                System.debug('Parsed QBO Response: ' + responseMap);

                Map<String, Object> qboCustomer =
                    (Map<String, Object>) responseMap.get('Customer');

                String qboCustomerId = String.valueOf(qboCustomer.get('Id'));
                System.debug('QBO Customer Id: ' + qboCustomerId);

                // Update ONLY required fields (avoid Name/FLS issue)
                Account accUpdate = new Account(
                    Id = acc.Id,
                    QBO_Customer_ID__c = qboCustomerId
                );

                update accUpdate;

                resp.message = 'Customer synced successfully to QBO';
            }
            // Error from QBO
            else {
                resp.message = 'QBO Error: ' + res.getBody();
                System.debug('QBO ERROR RESPONSE: ' + res.getBody());
            }

            responses.add(resp);
        }

        System.debug('=== QBOCustomerService END ===');
        return responses;
    }

    // ===== FLOW INPUT =====
    public class FlowRequest {
        @InvocableVariable(required=true)
        public Id accountId;
    }

    // ===== FLOW OUTPUT =====
    public class FlowResponse {
        @InvocableVariable
        public String message;
    }
}