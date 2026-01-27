global with sharing class QBO_PaymentBatch
    implements Database.Batchable<SObject>, Database.AllowsCallouts {

    global Database.QueryLocator start(Database.BatchableContext bc) {

        return Database.getQueryLocator([
            SELECT Id,
                   Status__c,
                   Amount__c,
                   QBO_Payment_ID__c,
                   Account__r.QBO_Customer_Id__c,
                   Invoice__r.QBO_Invoice_Id__c
            FROM Payment_Intent__c
            WHERE QBO_Payment_ID__c = NULL
            AND Status__c IN ('Succeeded', 'Succeed')
        ]);
    }

    global void execute(
        Database.BatchableContext bc,
        List<Payment_Intent__c> scope
    ) {
        List<Payment_Intent__c> updates = new List<Payment_Intent__c>();

        for (Payment_Intent__c pi : scope) {
            try {
                String qboPaymentId =
                    QBO_PaymentPushService.pushPaymentToQBO(pi);

                pi.QBO_Payment_ID__c = qboPaymentId;
                pi.Status__c = 'Paid';
                updates.add(pi);

            } catch (Exception e) {
                System.debug(
                    '❌ QBO payment failed for ' +
                    pi.Id + ' : ' + e.getMessage()
                );
            }
        }

        if (!updates.isEmpty()) {
            update updates;
        }
    }

    global void finish(Database.BatchableContext bc) {
        System.debug('✅ QBO Payment Batch completed successfully.');
    }
}