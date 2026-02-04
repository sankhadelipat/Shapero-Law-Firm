@IsTest
public class QBOExpenseService_Test {

    /* ============================================================
       HTTP CALLOUT MOCK
       ============================================================ */
    private class QBOExpenseServiceMock implements HttpCalloutMock {

        private Integer statusCode;
        private String responseBody;

        QBOExpenseServiceMock(Integer statusCode, String responseBody) {
            this.statusCode = statusCode;
            this.responseBody = responseBody;
        }

        public HttpResponse respond(HttpRequest req) {

            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            res.setHeader('Content-Type', 'application/json');
            res.setBody(responseBody);

            return res;
        }
    }

    /* ============================================================
       TEST SETUP (CUSTOM METADATA)
       ============================================================ */
    @TestSetup
    static void setupMetadata() {
        // Custom Metadata is readable in tests automatically
        // Ensure a record exists with DeveloperName = 'Default'
        // Realm_Id__c must be populated in org
    }

    /* ============================================================
       TEST: MULTIPLE PURCHASE RECORDS
       ============================================================ */
    @IsTest
    static void testFetchExpenses_MultiplePurchases() {

        String body =
            '{' +
                '"QueryResponse": {' +
                    '"Purchase": [' +
                        '{"Id": "EXP-1", "TotalAmt": 100},' +
                        '{"Id": "EXP-2", "TotalAmt": 200}' +
                    ']' +
                '}' +
            '}';

        Test.setMock(
            HttpCalloutMock.class,
            new QBOExpenseServiceMock(200, body)
        );

        Test.startTest();
        List<Map<String, Object>> result =
            QBOExpenseService.fetchExpenses(System.now().addDays(-1));
        Test.stopTest();

        System.assertEquals(2, result.size());
        System.assertEquals('EXP-1', result[0].get('Id'));
        System.assertEquals('EXP-2', result[1].get('Id'));
    }

    /* ============================================================
       TEST: SINGLE PURCHASE OBJECT
       ============================================================ */
    @IsTest
    static void testFetchExpenses_SinglePurchase() {

        String body =
            '{' +
                '"QueryResponse": {' +
                    '"Purchase": {' +
                        '"Id": "EXP-SINGLE",' +
                        '"TotalAmt": 150' +
                    '}' +
                '}' +
            '}';

        Test.setMock(
            HttpCalloutMock.class,
            new QBOExpenseServiceMock(200, body)
        );

        Test.startTest();
        List<Map<String, Object>> result =
            QBOExpenseService.fetchExpenses(System.now().addDays(-1));
        Test.stopTest();

        System.assertEquals(1, result.size());
        System.assertEquals('EXP-SINGLE', result[0].get('Id'));
    }

    /* ============================================================
       TEST: NO PURCHASE RETURNED
       ============================================================ */
    @IsTest
    static void testFetchExpenses_NoPurchases() {

        String body =
            '{' +
                '"QueryResponse": {}' +
            '}';

        Test.setMock(
            HttpCalloutMock.class,
            new QBOExpenseServiceMock(200, body)
        );

        Test.startTest();
        List<Map<String, Object>> result =
            QBOExpenseService.fetchExpenses(System.now().addDays(-1));
        Test.stopTest();

        System.assertEquals(0, result.size());
    }

    /* ============================================================
       TEST: HTTP ERROR HANDLING
       ============================================================ */
    @IsTest
    static void testFetchExpenses_HttpError() {

        Test.setMock(
            HttpCalloutMock.class,
            new QBOExpenseServiceMock(500, '{"Fault":"Server Error"}')
        );

        Test.startTest();
        try {
            QBOExpenseService.fetchExpenses(System.now().addDays(-1));
            System.assert(false, 'Exception should have been thrown');
        } catch (CalloutException ex) {
            System.assert(ex.getMessage().contains('Server Error'));
        }
        Test.stopTest();
    }
}