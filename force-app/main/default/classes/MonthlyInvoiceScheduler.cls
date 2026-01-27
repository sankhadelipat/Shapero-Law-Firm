public class MonthlyInvoiceScheduler implements Schedulable {
    public void execute(SchedulableContext sc) {
        Date today = Date.today();
        Date firstDayOfMonth = Date.newInstance(today.year(), today.month(), 1);
        Date lastDayOfMonth = firstDayOfMonth.addMonths(1).addDays(-1);

        if (today == lastDayOfMonth)
            Database.executeBatch(new MonthlyInvoiceBatch(), 50);
    }

    public static void scheduleJob() {
        String cronExpression = '0 0 0 1 * ? *'; // Run at midnight on the first day of every month
        String jobName = 'MonthlyInvoiceScheduler';
        System.schedule(jobName, cronExpression, new MonthlyInvoiceScheduler());
    }
}