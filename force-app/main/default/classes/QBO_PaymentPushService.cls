public with sharing class QBO_PaymentPushService {

    private static final String DEPOSIT_ACCOUNT_ID = '4'; // Undeposited Funds

    public static String pushPaymentToQBO(Payment_Intent__c pi) {

        if (pi == null) {
            throw new AuraHandledException('Payment Intent is required.');
        }

        if (pi.Status__c != 'Succeed' && pi.Status__c != 'Succeed') {
            throw new AuraHandledException(
                'Only payments with status "Succeeded" can be pushed.'
            );
        }

        Decimal amt = pi.Amount__c.setScale(2);

        String payload =
            '{' +
                '"TotalAmt": ' + amt + ',' +
                '"CustomerRef": {"value": "' + pi.Account__r.QBO_Customer_Id__c + '"},' +
                '"DepositToAccountRef": {"value": "' + DEPOSIT_ACCOUNT_ID + '"},' +
                '"Line": [{' +
                    '"Amount": ' + amt + ',' +
                    '"LinkedTxn": [{' +
                        '"TxnId": "' + pi.Invoice__r.QBO_Invoice_Id__c + '",' +
                        '"TxnType": "Invoice"' +
                    '}]' +
                '}]' +
            '}';

        System.debug('✅ QBO Payment Payload => ' + payload);

        QuickBooks_Config__mdt cfg =
            QuickBooks_Config__mdt.getInstance('Default');

        HttpRequest req = new HttpRequest();
        req.setMethod('POST');
        req.setEndpoint(
            'callout:QBO_Named_Credential/v3/company/' +
            cfg.Realm_Id__c +
            '/payment?minorversion=75'
        );
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Accept', 'application/json'); // IMPORTANT
        req.setBody(payload);

        Http http = new Http();
        HttpResponse res = http.send(req);

        System.debug('✅ QBO STATUS => ' + res.getStatusCode());
        System.debug('✅ QBO BODY => ' + res.getBody());

        if (res.getStatusCode() != 200 && res.getStatusCode() != 201) {
            throw new AuraHandledException(
                'QBO Payment failed (' + res.getStatusCode() + '): ' + res.getBody()
            );
        }

        Map<String, Object> response =
            (Map<String, Object>) JSON.deserializeUntyped(res.getBody());

        Map<String, Object> payment =
            (Map<String, Object>) response.get('Payment');

        return (String) payment.get('Id');
    }
}