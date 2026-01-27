global with sharing class QBO_PaymentBatchScheduler
    implements Schedulable {

    global void execute(SchedulableContext sc) {

        // Scope size = 1 (maximum safety for QBO)
        Database.executeBatch(
            new QBO_PaymentBatch(),
            1
        );
    }
}