global class QBOExpenseSyncScheduler implements Schedulable {

    global void execute(SchedulableContext sc) {
        System.enqueueJob(new QBOExpenseSyncQueueable(0));
    }
}