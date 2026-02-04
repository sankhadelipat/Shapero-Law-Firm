@IsTest
public class QuickBooksCustomerService_Test {

    private class QBOCustomerMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {

            HttpResponse res = new HttpResponse();
            res.setStatusCode(201);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"Customer":{"Id":"45"}}');

            return res;
        }
    }

    @IsTest
    static void testFutureCallout() {

        Id personRtId = Schema.SObjectType.Account
            .getRecordTypeInfosByName()
            .get('Person Account')
            .getRecordTypeId();

        Account acc = new Account(
            RecordTypeId = personRtId,
            FirstName = 'John',
            LastName = 'Doe',
            PersonEmail = 'john@test.com'
        );
        insert acc;

        Test.setMock(HttpCalloutMock.class, new QBOCustomerMock());

        Test.startTest();
        QuickBooksCustomerService.createCustomers(
            new List<Id>{ acc.Id }
        );
        Test.stopTest(); // @future executes HERE

        Account updated = [
            SELECT QBO_Customer_ID__c
            FROM Account
            WHERE Id = :acc.Id
        ];

        System.assertEquals(
            '45',
            updated.QBO_Customer_ID__c
        );
    }
}