public without sharing class QBO_PaymentIntentQueueable implements Queueable, Database.AllowsCallouts {

    private static final String DEPOSIT_ACCOUNT_ID = '4';

    private List<Id> paymentIntentIds;

    public QBO_PaymentIntentQueueable(List<Id> piIds) {
        this.paymentIntentIds = piIds;
    }

   public static void enqueue(List<Payment_Intent__c> newList) {

    List<Id> ids = new List<Id>();

    Set<String> SUCCESS_STATUSES = new Set<String>{'Succeed'};

    for (Payment_Intent__c pi : newList) {

        System.debug('INSERT PI => ' + pi.Id);
        System.debug('Status => ' + pi.Status__c);
        System.debug('Invoice => ' + pi.Invoice__c);

        if (
            SUCCESS_STATUSES.contains(pi.Status__c) &&
            pi.QBO_Payment_ID__c == null &&
            pi.Invoice__c != null
        ) {
            ids.add(pi.Id);
        }
    }

    
    System.debug('ids => ' + ids);
    if (!ids.isEmpty()) {
        System.enqueueJob(
            new QBO_PaymentIntentQueueable(ids)
        );
    }
}


    /* ===============================
       QUEUEABLE EXECUTION
       =============================== */
    public void execute(QueueableContext qc) {

        system.debug('running execute on QBO_PaymentIntentQueueable');
        system.debug('paymentIntentIds => ' + paymentIntentIds);
        List<Payment_Intent__c> scope = [
            SELECT Id,
                   Status__c,
                   Amount__c,
                   QBO_Payment_ID__c,
                   Account__r.QBO_Customer_Id__c,
                   Invoice__r.QBO_Invoice_Id__c
            FROM Payment_Intent__c
            WHERE Id IN :paymentIntentIds
            AND QBO_Payment_ID__c = NULL
            AND Status__c = 'Succeed'
        ];
        system.debug('scope=> ' + scope);

        List<Payment_Intent__c> updates = new List<Payment_Intent__c>();

        for (Payment_Intent__c pi : scope) {
            try {
                String qboPaymentId = pushPaymentToQBO(pi);

                pi.QBO_Payment_ID__c = qboPaymentId;
                pi.Status__c = 'Paid';
                updates.add(pi);

            } catch (Exception e) {
                System.debug(
                    'QBO payment failed for ' +
                    pi.Id + ' : ' + e.getMessage()
                );
            }
        }

        if (!updates.isEmpty()) {
            update updates;
        }
    }

    private static String pushPaymentToQBO(Payment_Intent__c pi) {

        Decimal amt = pi.Amount__c.setScale(2);
Date d = Date.today();
String txnDate = 
    d.year() + '-' +
    String.valueOf(d.month()).leftPad(2, '0') + '-' +
    String.valueOf(d.day()).leftPad(2, '0');

String payload =
'{' +
  '"TotalAmt": ' + amt + ',' +
  '"CustomerRef": {' +
    '"value": "' + pi.Account__r.QBO_Customer_Id__c + '"' +
  '},' +
  '"DepositToAccountRef": {' +
    '"value": "' + DEPOSIT_ACCOUNT_ID + '"' +
  '},' +
  '"TxnDate": "' + txnDate + '",' +
  '"Line": [' +
    '{' +
      '"Amount": ' + amt + ',' +
      '"LinkedTxn": [' +
        '{' +
          '"TxnId": "' + pi.Invoice__r.QBO_Invoice_Id__c + '",' +
          '"TxnType": "Invoice"' +
        '}' +
      ']' +
    '}' +
  ']' +
'}';

        System.debug('QBO Payment Payload => ' + payload);

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
        req.setHeader('Accept', 'application/json');
        req.setBody(payload);

        Http http = new Http();
        HttpResponse res = http.send(req);

        System.debug('QBO STATUS => ' + res.getStatusCode());
        System.debug('QBO BODY => ' + res.getBody());

        if (res.getStatusCode() != 200 &&
            res.getStatusCode() != 201) {
            throw new CalloutException(
                'QBO Payment failed (' +
                res.getStatusCode() + '): ' +
                res.getBody()
            );
        }

        Map<String, Object> response =
            (Map<String, Object>) JSON.deserializeUntyped(res.getBody());

        Map<String, Object> payment =
            (Map<String, Object>) response.get('Payment');

        return (String) payment.get('Id');
    }
}