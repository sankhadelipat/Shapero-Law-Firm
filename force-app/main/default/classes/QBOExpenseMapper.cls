public class QBOExpenseMapper {

    private static Id DEFAULT_ACCOUNT_ID;

    /* ============================================================
       PUBLIC ENTRY
       ============================================================ */
    public static List<Expense__c> mapToSalesforce(List<Map<String, Object>> qboExpenses) {
        List<Expense__c> toUpsert = new List<Expense__c>();
        Set<String> qboIds = new Set<String>();

        // Collect QBO IDs
        for (Map<String, Object> qbo : qboExpenses) {
            if (qbo.containsKey('Id')) {
                qboIds.add(String.valueOf(qbo.get('Id')));
            }
        }

        // Fetch existing expenses
        Map<String, Expense__c> existingMap = fetchExistingExpenses(qboIds);

        for (Map<String, Object> qbo : qboExpenses) {
            String qboId = String.valueOf(qbo.get('Id'));
            Expense__c existing = existingMap.get(qboId);

            Expense__c incoming = buildExpense(qbo, existing);

            // Skip null expenses (rare, only if mapping failed)
            if (incoming == null) continue;

            if (existing != null) {
                if (hasChanged(existing, incoming)) {
                    incoming.Id = existing.Id; // update
                    toUpsert.add(incoming);
                }
            } else {
                toUpsert.add(incoming); // new record
            }
        }

        return toUpsert;
    }

    /* ============================================================
       EXISTING RECORDS
       ============================================================ */
    private static Map<String, Expense__c> fetchExistingExpenses(Set<String> qboIds) {
        Map<String, Expense__c> mapExp = new Map<String, Expense__c>();
        if (!qboIds.isEmpty()) {
            for (Expense__c e : [
                SELECT Id, QBO_Expense_ID__c,
                       Amount__c, Expense_Date__c,
                       Description__c, Category__c,
                       Account__c, Invoice__c
                FROM Expense__c     
                WHERE QBO_Expense_ID__c IN :qboIds
            ]) {
                mapExp.put(e.QBO_Expense_ID__c, e);
            }
        }
        return mapExp;
    }

    private static Boolean hasChanged(Expense__c oldRec, Expense__c newRec) {
        return oldRec.Amount__c        != newRec.Amount__c ||
               oldRec.Expense_Date__c != newRec.Expense_Date__c ||
               oldRec.Description__c  != newRec.Description__c ||
               oldRec.Category__c     != newRec.Category__c ||
               oldRec.Account__c      != newRec.Account__c ||
               oldRec.Invoice__c      != newRec.Invoice__c;
    }

    public static Expense__c buildExpense(
    Map<String, Object> qbo,
    Expense__c existing
) {
    // Preserve existing record when updating
    Expense__c exp = existing != null
        ? existing.clone(false, true, false, false)
        : new Expense__c();

    /* ===============================
       ACCOUNT RESOLUTION
       =============================== */
    Id accountId = resolveAccountFromQBO(qbo);

    if (accountId != null) {
        exp.Account__c = accountId;
    } else if (existing == null) {
        exp.Account__c = getDefaultAccountId();
    }

    /* ===============================
       CORE FIELDS (SAFE OVERWRITE)
       =============================== */
    exp.QBO_Expense_ID__c = String.valueOf(qbo.get('Id'));

    if (qbo.containsKey('TotalAmt')) {
        exp.Amount__c = (Decimal) qbo.get('TotalAmt');
    }

    if (qbo.containsKey('TxnDate')) {
        exp.Expense_Date__c =
            Date.valueOf((String) qbo.get('TxnDate'));
    }

    /* ===============================
       DESCRIPTION (LINE-LEVEL SAFE)
       =============================== */
    String description;

    List<Object> lines = (List<Object>) qbo.get('Line');
    if (lines != null && !lines.isEmpty()) {
        Map<String, Object> firstLine =
            (Map<String, Object>) lines[0];

        description = (String) firstLine.get('Description');
    }

    // Only update if QBO actually sent a value
    if (!String.isBlank(description)) {
        exp.Description__c = description;
    }

    /* ===============================
       REMAINING FIELDS
       =============================== */
    String category = mapCategory(getCategoryFromQBO(qbo));
    if (!String.isBlank(category)) {
        exp.Category__c = category;
    }

    // Status only on create
    if (existing == null) {
        exp.Status__c = 'Unassigned';
    }

    exp.QBO_Sync_Status__c = 'Synced';
    exp.Last_Sync_Date__c  = System.now();
    exp.QBO_Sync_Error__c  = null;

    return exp;
}


    /* ============================================================
       RESOLVE ACCOUNT
       ============================================================ */
    private static Id resolveAccountFromQBO(Map<String, Object> qbo) {
        if (qbo.containsKey('EntityRef')) {
            Map<String, Object> entityRef = (Map<String, Object>) qbo.get('EntityRef');
            if (entityRef != null && 'Customer'.equals(entityRef.get('type')) && entityRef.containsKey('value')) {
                String qboCustomerId = (String) entityRef.get('value');
                List<Account> accs = [SELECT Id FROM Account WHERE QBO_Customer_ID__c = :qboCustomerId LIMIT 1];
                return accs.isEmpty() ? null : accs[0].Id;
            }
        }
        return null;
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
        if (qbo.containsKey('Line') && qbo.get('Line') instanceof List<Object>) {
            List<Object> lines = (List<Object>) qbo.get('Line');
            if (!lines.isEmpty()) {
                Map<String, Object> firstLine = (Map<String, Object>) lines[0];
                if ('AccountBasedExpenseLineDetail'.equals(firstLine.get('DetailType'))) {
                    Map<String, Object> detail = (Map<String, Object>) firstLine.get('AccountBasedExpenseLineDetail');
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
        return categoryMap.containsKey(qboCategory) ? categoryMap.get(qboCategory) : 'Service Fees';
    }

    /* ============================================================
       INVOICE
       ============================================================ */
    private static String getLinkedInvoiceId(Map<String, Object> qbo) {
        if (!qbo.containsKey('LinkedTxn')) return null;
        List<Object> txns = (List<Object>) qbo.get('LinkedTxn');
        for (Object obj : txns) {
            Map<String, Object> txn = (Map<String, Object>) obj;
            if ('Invoice'.equals(txn.get('TxnType'))) {
                return (String) txn.get('TxnId');
            }
        }
        return null;
    }

    public static Invoice__c findInvoiceByQBOId(String qboInvoiceId) {
        if (String.isBlank(qboInvoiceId)) return null;
        List<Invoice__c> invs = [SELECT Id FROM Invoice__c WHERE QBO_Invoice_ID__c = :qboInvoiceId LIMIT 1];
        return invs.isEmpty() ? null : invs[0];
    }
}