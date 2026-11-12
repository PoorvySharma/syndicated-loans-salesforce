/**
 * Separation of duties: lifecycle actions require the Syndication_Operate custom permission
 * (granted by the Admin and Operator permission sets, not by Read Only).
 */
public with sharing class SyndicationSecurity {
    public static final String OPERATE = 'Syndication_Operate';

    public static Boolean isOperator() {
        return FeatureManagement.checkPermission(OPERATE);
    }

    public static void requireOperator() {
        if (!isOperator()) {
            throw new LoanException('You need the Syndication Operator or Admin permission set to perform this action.');
        }
    }
}
