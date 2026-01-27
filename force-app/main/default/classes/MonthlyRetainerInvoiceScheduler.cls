/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : MonthlyRetainerInvoiceScheduler
 * Author          : <YourName>
 * Created Date    : Jan 20, 2026
 * Last Modified By: <YourName>
 * Last Modified On: Jan 20, 2026
 * Description     : This class implements for......
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Jan 20, 2026  │ <YourName>   │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */

public class MonthlyRetainerInvoiceScheduler {

	public static void executeSchedule(){
		System.schedule(
			'Monthly Contract Invoice Job',
			'0 0 2 * * ?',
			new ContractToMonthlyIncoiceBatch()
		);
	}

}