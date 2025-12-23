public with sharing class LeadStatusTimeController {

    @AuraEnabled(cacheable=true)
    public static List<StageTimeDTO> getLeadTimeSummary() {
        List<AggregateResult> raw = [
            SELECT 
                AVG(Time_spent_in_Contacted__c) avgContacted,
                AVG(Time_spent_in_Not_Contacted__c) avgNotContacted,
                AVG(Time_spent_in_Nurturing__c) avgNurturing,
                AVG(Time_spent_in_Qualified__c) avgRetainerSent,
                AVG(Time_spent_in_Retainer_Signed__c) avgRetainerSigned
            FROM Lead WHERE Last_Status_Change__c != null
        ];

        List<StageTimeDTO> result = new List<StageTimeDTO>();
        AggregateResult ar = raw[0];

        add(result, 'Contacted',        ar.get('avgContacted'));
        add(result, 'Not Contacted',    ar.get('avgNotContacted'));
        add(result, 'Nurturing',        ar.get('avgNurturing'));
        add(result, 'Retainer Sent',    ar.get('avgRetainerSent'));
        add(result, 'Retainer Signed',  ar.get('avgRetainerSigned'));
        system.debug('result--> '+result);
        return result;
    }

    private static void add(List<StageTimeDTO> out, String label, Object minsObj) {
        Integer mins = (minsObj == null) ? 0 : ((Decimal)minsObj).intValue();
        out.add(new StageTimeDTO(label, mins));
    }

    public class StageTimeDTO {
        @AuraEnabled public String stage;
        @AuraEnabled public Integer minutes;
        @AuraEnabled public String shortLabel;

        public StageTimeDTO(String s, Integer m) {
            stage = s;
            minutes = m;
            shortLabel = formatLabel(m);
        }

        private String formatLabel(Integer m) {
            Integer days = m / 1440;
            Integer hours = Math.mod(m, 1440) / 60;
            Integer mins = Math.mod(m, 60);

            return days + 'D ' + hours + 'H ' + mins + 'M';
        }
    }
}