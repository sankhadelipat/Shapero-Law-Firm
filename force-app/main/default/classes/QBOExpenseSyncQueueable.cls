public class QBOExpenseSyncQueueable
    implements Queueable, Database.AllowsCallouts {

    private Integer retryCount;
    private static final Integer MAX_RETRIES = 3;

    // store logs in memory
    private List<Logger__c> logs = new List<Logger__c>();

    public QBOExpenseSyncQueueable(Integer retryCount) {
        this.retryCount = retryCount;
    }

    public void execute(QueueableContext context) {

        String CLASS_NAME = 'QBOExpenseSyncQueueable';
        String METHOD_NAME = 'execute';

        try {
            // 🚫 NO DML BEFORE CALLOUT

            Datetime lastRun =
                QBOExpenseSyncUtil.getLastSuccessfulRun();

            List<Map<String, Object>> qboExpenses =
                QBOExpenseService.fetchExpenses(lastRun);

            List<Expense__c> expenses =
                QBOExpenseMapper.mapToSalesforce(qboExpenses);

            if (!expenses.isEmpty()) {
                upsert expenses QBO_Expense_ID__c;
            }

            QBOExpenseSyncUtil.updateLastSuccessfulRun(System.now());

            addLog(
                'Success',
                'QBO Expense Sync SUCCESS | Records=' + expenses.size(),
                CLASS_NAME,
                METHOD_NAME,
                null,
                null
            );

        } catch (Exception ex) {

            addLog(
                'Error',
                'QBO Expense Sync FAILED | ' + ex.getMessage(),
                CLASS_NAME,
                METHOD_NAME,
                null,
                ex.getStackTraceString()
            );

            if (retryCount < MAX_RETRIES) {
                System.enqueueJob(
                    new QBOExpenseSyncQueueable(retryCount + 1)
                );
            }
        }

        addLog(
            'Info',
            'QBO Expense Sync END | Retry=' + retryCount,
            CLASS_NAME,
            METHOD_NAME,
            null,
            null
        );

        // ✅ ONE DML AT THE END (SAFE)
        if (!logs.isEmpty()) {
            insert logs;
        }
    }

    /* =========================
       LOG COLLECTOR (NO DML)
       ========================= */
    private void addLog(
        String status,
        String message,
        String className,
        String methodName,
        Id recordId,
        String stackTrace
    ) {
        Logger__c lg = new Logger__c();
        lg.Status__c = status;
        lg.Message__c = message;
        lg.Class_Name__c = className;
        lg.Method_Name__c = methodName;
        lg.Record_Id__c = recordId;
        lg.Stack_Trace__c = stackTrace;
        logs.add(lg);
    }
}