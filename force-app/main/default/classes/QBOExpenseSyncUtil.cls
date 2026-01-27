public class QBOExpenseSyncUtil {
    public static Datetime getLastSuccessfulRun() {

        QBO_Sync_Config__c cs = QBO_Sync_Config__c.getOrgDefaults();

        if (cs == null || cs.Last_Successful_Run__c == null) {
            return System.now().addDays(-1);
        }

        return cs.Last_Successful_Run__c;
    }

   // Updates the last successful sync time.
    public static void updateLastSuccessfulRun(Datetime dt) {

        QBO_Sync_Config__c cs = QBO_Sync_Config__c.getOrgDefaults();

        if (cs == null) {
            cs = new QBO_Sync_Config__c();
        }

        cs.Last_Successful_Run__c = dt;
        upsert cs;
    }
}