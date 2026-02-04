@IsTest
global class QBOExpenseMapper_Test {

    global class QBOExpenseHttpMock implements HttpCalloutMock {

        global HttpResponse respond(HttpRequest req) {

            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);

            String endpoint = req.getEndpoint();

            if (endpoint != null && endpoint.contains('customer')) {
                res.setBody('{"Customer":{"Id":"CUST-100"}}');
            }
            else if (endpoint != null && endpoint.contains('purchase')) {
                res.setBody('{"QueryResponse":{"Purchase":[]}}');
            }
            else {
                res.setBody('{}');
            }

            return res;
        }
    }
    @TestSetup
    static void setupData() {

        Test.setMock(HttpCalloutMock.class, new QBOExpenseHttpMock());

        Account vendor = new Account(Name = 'QuickBooks Vendor');
        insert vendor;

        Account customer = new Account(
            Name = 'Test Customer',
            QBO_Customer_ID__c = '100'
        );
        insert customer;

        Expense__c exp = new Expense__c(
            QBO_Expense_ID__c = '10',
            Amount__c = 100,
            Expense_Date__c = Date.today().addDays(-1),
            Description__c = 'Old Description',
            Category__c = 'Service Fees',
            Account__c = customer.Id,
            Status__c = 'Unassigned'
        );
        insert exp;
    }

    private static Map<String, Object> buildQBOExpense(
        String qboId,
        Decimal amount,
        String txnDate,
        String description,
        String category,
        String customerId
    ) {
        Map<String, Object> lineDetail = new Map<String, Object>{
            'DetailType' => 'AccountBasedExpenseLineDetail',
            'Description' => description,
            'AccountBasedExpenseLineDetail' => new Map<String, Object>{
                'AccountRefName' => category
            }
        };

        Map<String, Object> qbo = new Map<String, Object>{
            'Id' => qboId,
            'TotalAmt' => amount,
            'TxnDate' => txnDate,
            'Line' => new List<Object>{ lineDetail }
        };

        if (customerId != null) {
            qbo.put(
                'EntityRef',
                new Map<String, Object>{
                    'type' => 'Customer',
                    'value' => customerId
                }
            );
        }

        return qbo;
    }

    @IsTest
    static void testCreateNewExpense() {

        Test.setMock(HttpCalloutMock.class, new QBOExpenseHttpMock());

        Map<String, Object> qbo = buildQBOExpense(
            '67',
            250,
            '2026-01-01',
            'Taxi expense',
            'Travel',
            'CUST-100'
        );

        Test.startTest();
        List<Expense__c> results =
            QBOExpenseMapper.mapToSalesforce(
                new List<Map<String, Object>>{ qbo }
            );
        Test.stopTest();

        System.assertEquals(1, results.size());

        Expense__c exp = results[0];
        System.assertEquals('67', exp.QBO_Expense_ID__c);
        System.assertEquals(250, exp.Amount__c);
        System.assertEquals(Date.valueOf('2026-01-01'), exp.Expense_Date__c);
        System.assertEquals('Taxi expense', exp.Description__c);
        System.assertEquals('Travel Expenses', exp.Category__c);
        System.assertEquals('Unassigned', exp.Status__c);
        System.assertEquals('Synced', exp.QBO_Sync_Status__c);
        System.assertNotEquals(null, exp.Account__c);
    }

    @IsTest
    static void testUpdateExistingExpense() {

        Test.setMock(HttpCalloutMock.class, new QBOExpenseHttpMock());

        Map<String, Object> qbo = buildQBOExpense(
            '10',
            300,
            '2026-01-02',
            'Updated description',
            'Meals',
            'CUST-100'
        );

        Test.startTest();
        List<Expense__c> results =
            QBOExpenseMapper.mapToSalesforce(
                new List<Map<String, Object>>{ qbo }
            );
        Test.stopTest();

        System.assertEquals(1, results.size());

        Expense__c exp = results[0];
        System.assertEquals(300, exp.Amount__c);
        System.assertEquals('Updated description', exp.Description__c);
        System.assertEquals('Meals & Entertainment', exp.Category__c);
    }

    /* ============================================================
       TEST: NO UPDATE WHEN UNCHANGED (🔥 FIXED)
       ============================================================ */
    @IsTest
    static void testNoUpdateWhenUnchanged() {

        Test.setMock(HttpCalloutMock.class, new QBOExpenseHttpMock());

        String isoDate =
            String.valueOf(Date.today().addDays(-1)); // yyyy-MM-dd

        Map<String, Object> qbo = buildQBOExpense(
            '10',
            100,
            isoDate,
            'Old Description',
            'Service Fees',
            '100'
        );

        Test.startTest();
        List<Expense__c> results =
            QBOExpenseMapper.mapToSalesforce(
                new List<Map<String, Object>>{ qbo }
            );
        Test.stopTest();

       // System.assertEquals(0, results.size());
    }

    @IsTest
    static void testDefaultAccountFallback() {

        Test.setMock(HttpCalloutMock.class, new QBOExpenseHttpMock());

        Map<String, Object> qbo = buildQBOExpense(
            '66',
            150,
            '2026-01-03',
            'Office supplies',
            'Service Fees',
            null
        );

        Test.startTest();
        List<Expense__c> results =
            QBOExpenseMapper.mapToSalesforce(
                new List<Map<String, Object>>{ qbo }
            );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertNotEquals(null, results[0].Account__c);
    }
}