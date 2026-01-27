public class QBOExpenseMapper {

    private static Id DEFAULT_ACCOUNT_ID;

    /* ============================================================
       PUBLIC ENTRY
       ============================================================ */

    public static List<Expense__c> mapToSalesforce(
        List<Map<String, Object>> qboExpenses
    ) {
        List<Expense__c> toUpsert = new List<Expense__c>();
        Set<String> qboIds = new Set<String>();

        for (Map<String, Object> qbo : qboExpenses) {
            if (qbo.containsKey('Id')) {
                qboIds.add(String.valueOf(qbo.get('Id')));
            }
        }

        Map<String, Expense__c> existingMap =
            fetchExistingExpenses(qboIds);

        for (Map<String, Object> qbo : qboExpenses) {

            Expense__c incoming = buildExpense(qbo);
            String qboId = incoming.QBO_Expense_ID__c;

            if (existingMap.containsKey(qboId)) {
                Expense__c existing = existingMap.get(qboId);

                if (hasChanged(existing, incoming)) {
                    incoming.Id = existing.Id; // ✅ REQUIRED
                    toUpsert.add(incoming);
                }
            } else {
                toUpsert.add(incoming);
            }
        }
        return toUpsert;
    }

    /* ============================================================
       EXISTING RECORDS
       ============================================================ */

    private static Map<String, Expense__c> fetchExistingExpenses(
        Set<String> qboIds
    ) {
        Map<String, Expense__c> mapExp = new Map<String, Expense__c>();
        if (!qboIds.isEmpty()) {
            for (Expense__c e : [
                SELECT Id, QBO_Expense_ID__c,
                       Amount__c, Expense_Date__c,
                       Description__c, Category__c, Account__c,Invoice__c
                FROM Expense__c     
                WHERE QBO_Expense_ID__c IN :qboIds
            ]) {
                mapExp.put(e.QBO_Expense_ID__c, e);
            }
        }
        return mapExp;
    }

    private static Boolean hasChanged(
        Expense__c oldRec,
        Expense__c newRec
    ) {
        return oldRec.Amount__c        != newRec.Amount__c ||
               oldRec.Expense_Date__c != newRec.Expense_Date__c ||
               oldRec.Description__c != newRec.Description__c ||
               oldRec.Category__c    != newRec.Category__c ||
               oldRec.Account__c     != newRec.Account__c ||
               oldRec.Invoice__c	 != newRec.Invoice__c;
    }

    /* ============================================================
       BUILD EXPENSE
       ============================================================ */

    public static Expense__c buildExpense(Map<String, Object> qbo) {

        Expense__c exp = new Expense__c();

        /* -------- REQUIRED: Account -------- */
        Id accountId = resolveAccountFromQBO(qbo);
        exp.Account__c = accountId != null
            ? accountId
            : getDefaultAccountId();

        /* -------- Category -------- */
        exp.Category__c = mapCategory(getCategoryFromQBO(qbo));
        exp.QBO_Expense_ID__c  = String.valueOf(qbo.get('Id'));
        exp.Amount__c          = (Decimal) qbo.get('TotalAmt');
        exp.Expense_Date__c    = Date.valueOf((String) qbo.get('TxnDate'));
        exp.Description__c     = (String) qbo.get('PrivateNote');
        exp.Status__c          = 'Unassigned';
        exp.QBO_Sync_Status__c = 'Synced';
        exp.Last_Sync_Date__c  = System.now();
        exp.QBO_Sync_Error__c  = null;

        return exp;
    }

 private static Id resolveAccountFromQBO(Map<String, Object> qbo) {

    if (!qbo.containsKey('EntityRef')) return null;

    Map<String, Object> entityRef =
        (Map<String, Object>) qbo.get('EntityRef');

    if (entityRef == null || !entityRef.containsKey('value')) return null;

    String entityId   = (String) entityRef.get('value');
    String entityType = (String) entityRef.get('type');

    // ✅ Only match Accounts when it's a Customer
    if (entityType == 'Customer') {
        List<Account> accs = [
            SELECT Id
            FROM Account
            WHERE QBO_Customer_ID__c = :entityId
            LIMIT 1
        ];
        return accs.isEmpty() ? null : accs[0].Id;
    }

    return null; // Vendor → handled elsewhere
}


    private static Id getDefaultAccountId() {
        if (DEFAULT_ACCOUNT_ID == null) {
            DEFAULT_ACCOUNT_ID = [
                SELECT Id
                FROM Account
                WHERE Name = 'QuickBooks Vendor'
                LIMIT 1
            ].Id;
        }
        return DEFAULT_ACCOUNT_ID;
    }

    /* ============================================================
       CATEGORY
       ============================================================ */

    public static String getCategoryFromQBO(Map<String, Object> qbo) {
        if (qbo.containsKey('Line') &&
            qbo.get('Line') instanceof List<Object>) {

            List<Object> lines = (List<Object>) qbo.get('Line');
            if (!lines.isEmpty()) {
                Map<String, Object> firstLine =
                    (Map<String, Object>) lines[0];

                if (firstLine.get('DetailType') ==
                    'AccountBasedExpenseLineDetail') {

                    Map<String, Object> detail =
                        (Map<String, Object>)
                        firstLine.get('AccountBasedExpenseLineDetail');

                    return (String) detail.get('AccountRefName');
                }
            }
        }
        return 'Service Fees';
    }

    public static String mapCategory(String qboCategory) {
        Map<String, String> categoryMap = new Map<String, String>{
            'Service Fees' => 'Service Fees',
            'Travel'       => 'Travel Expenses',
            'Meals'        => 'Meals & Entertainment'
        };
        return categoryMap.containsKey(qboCategory)
            ? categoryMap.get(qboCategory)
            : 'Service Fees';
    }

    /* ============================================================
       INVOICE
       ============================================================ */

    private static String getLinkedInvoiceId(Map<String, Object> qbo) {

        if (!qbo.containsKey('LinkedTxn')) return null;

        List<Object> txns = (List<Object>) qbo.get('LinkedTxn');
        for (Object obj : txns) {
            Map<String, Object> txn = (Map<String, Object>) obj;
            if (txn.get('TxnType') == 'Invoice') {
                return (String) txn.get('TxnId');
            }
        }
        return null;
    }

    public static Invoice__c findInvoiceByQBOId(String qboInvoiceId) {
        if (String.isBlank(qboInvoiceId)) return null;

        List<Invoice__c> invs = [
            SELECT Id
            FROM Invoice__c
            WHERE QBO_Invoice_ID__c = :qboInvoiceId
            LIMIT 1
        ];
        return invs.isEmpty() ? null : invs[0];
    }
}