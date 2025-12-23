@isTest
public class LeadStatusTimeControllerTest
{
 	@isTest
    static void testingMethod()
    {
        Lead l = new Lead();
        l.FirstName = 'Test_FirstName';
        l.LastName = 'Test_LastName';
        l.Last_Status_Change__c = System.now();
        l.Time_in_Contacted__c = 0;
        l.Time_in_Not_Contacted__c = 0;
        l.Time_in_Nurturing__c = 0;
        l.Time_in_Qualified__c =0;
        l.Time_in_Unqualified__c = 0;
        l.Time_in_Unqualified__c = 0;
        insert l;
        LeadStatusTimeController.getLeadTimeSummary();
        
    }
}