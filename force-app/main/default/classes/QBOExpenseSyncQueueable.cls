public class QBOExpenseSyncQueueable
    implements Queueable, Database.AllowsCallouts {

    private Integer retryCount;
    private static final Integer MAX_RETRIES = 3;

    public QBOExpenseSyncQueueable(Integer retryCount) {
        this.retryCount = retryCount;
    }

    public void execute(QueueableContext context) {

        System.debug('QBO Expense Sync START | Retry=' + retryCount);

        try {
            Datetime lastRun =
                QBOExpenseSyncUtil.getLastSuccessfulRun();

            List<Map<String, Object>> qboExpenses =
                QBOExpenseService.fetchExpenses(lastRun);

            List<Expense__c> expenses =
                QBOExpenseMapper.mapToSalesforce(qboExpenses);

            if (!expenses.isEmpty()) {
                upsert expenses QBO_Expense_ID__c;
            }

            System.debug(
                'QBO Expense Sync SUCCESS | Records=' +
                expenses.size()
            );

            QBOExpenseSyncUtil.updateLastSuccessfulRun(System.now());

        } catch (Exception ex) {

            System.debug(
                'QBO Expense Sync FAILED | ' + ex.getMessage()
            );

            if (retryCount < MAX_RETRIES) {
                System.enqueueJob(
                    new QBOExpenseSyncQueueable(retryCount + 1)
                );
            }
        }

        System.debug('QBO Expense Sync END');
    }
}