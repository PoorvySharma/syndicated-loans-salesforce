@IsTest
private class ConsoleAndRestTest {
    private static User operator() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        User u = new User(
            Alias = 'slop', Email = 'sl.operator@example.com', EmailEncodingKey = 'UTF-8', LastName = 'Operator',
            LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_US', ProfileId = p.Id, TimeZoneSidKey = 'America/Chicago',
            Username = 'sl.operator.' + System.currentTimeMillis() + '@example.com'
        );
        insert u;
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = [SELECT Id FROM PermissionSet WHERE Name = 'Syndication_Admin'].Id);
        return u;
    }

    @IsTest
    static void consoleDrivesTheWholeLifecycle() {
        User u = operator();
        System.runAs(u) {
            TestDataFactory.Scenario s = TestDataFactory.syndication();
            Assert.isFalse(SyndicationConsoleController.getDeals().isEmpty());

            Assert.isTrue(SyndicationConsoleController.perform('ALLOCATE', s.facility.Id, null, null).startsWith('Allocated'));
            try {
                SyndicationConsoleController.perform('CLOSE_FACILITY', s.facility.Id, null, null);
                Assert.fail('expected CP gate');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('precedent'));
            }
            s.deal.CPs_Satisfied__c = true;
            update s.deal;
            SyndicationConsoleController.perform('CLOSE_FACILITY', s.facility.Id, null, null);

            SyndicationConsoleController.perform('REQUEST_DRAWDOWN', s.facility.Id, 25000000, Date.today());
            Id ddId = [SELECT Id FROM Drawdown__c WHERE Facility__c = :s.facility.Id LIMIT 1].Id;
            Assert.isTrue(SyndicationConsoleController.perform('NOTIFY_DRAWDOWN', ddId, null, null).contains('notified'));
            SyndicationConsoleController.perform('FUND_DRAWDOWN', ddId, null, null);
            SyndicationConsoleController.perform('OPEN_PERIOD', ddId, null, null);
            Id ipId = [SELECT Id FROM Interest_Period__c WHERE Drawdown__c = :ddId LIMIT 1].Id;
            SyndicationConsoleController.perform('FIX_RATE', ipId, 4.5, null);
            Assert.isTrue(SyndicationConsoleController.perform('CALC_INTEREST', ipId, null, null).startsWith('Interest calculated'));
            SyndicationConsoleController.perform('MARK_PAID', ipId, null, null);
            Assert.isTrue(SyndicationConsoleController.perform('DISTRIBUTE', ipId, null, null).contains('3 lenders'));
            SyndicationConsoleController.perform('REPAY_DRAWDOWN', ddId, null, null);

            Map<String, Object> board = SyndicationConsoleController.getBoard(s.deal.Id);
            Assert.areEqual(1, ((List<Facility__c>) board.get('facilities')).size());

            // Business-rule rejections surface to the UI as a message, not an exception.
            SyndicationConsoleController.perform('REQUEST_DRAWDOWN', s.facility.Id, 999000000, Date.today());
            Id bigId = [SELECT Id FROM Drawdown__c WHERE Amount__c = 999000000 LIMIT 1].Id;
            Assert.isTrue(SyndicationConsoleController.perform('NOTIFY_DRAWDOWN', bigId, null, null).startsWith('Drawdown rejected'));

            try {
                SyndicationConsoleController.perform('NOPE', s.facility.Id, null, null);
                Assert.fail('expected exception');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('Unknown action'));
            }
        }
    }

    @IsTest
    static void consoleActionsRequireOperatePermission() {
        // The running admin has not been granted the Syndication permission sets.
        TestDataFactory.Scenario s = TestDataFactory.syndication();
        try {
            SyndicationConsoleController.perform('ALLOCATE', s.facility.Id, null, null);
            Assert.fail('expected permission failure');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('permission set'));
        }
    }

    private static Map<String, Object> post(String resource, Map<String, Object> body) {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/syndication/v1/' + resource;
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(body));
        RestContext.request = req;
        RestContext.response = new RestResponse();
        SyndicationRestApi.handle();
        Map<String, Object> out = (Map<String, Object>) JSON.deserializeUntyped(RestContext.response.responseBody.toString());
        out.put('httpStatus', RestContext.response.statusCode);
        return out;
    }

    @IsTest
    static void restApiCreatesDrawdownAndFixesRate() {
        User u = operator();
        System.runAs(u) {
            TestDataFactory.Scenario s = TestDataFactory.activeFacility();
            Map<String, Object> r = post('drawdowns', new Map<String, Object>{ 'facilityId' => s.facility.Id, 'amount' => 5000000, 'valueDate' => String.valueOf(Date.today()) });
            Assert.areEqual(200, r.get('httpStatus'));
            Assert.areEqual('Notified', r.get('status'));

            Id ddId = Id.valueOf(String.valueOf(r.get('id')));
            DrawdownService.confirmFunding(ddId, true);
            Interest_Period__c p = InterestService.openNext(ddId);
            Map<String, Object> rate = post('rates', new Map<String, Object>{ 'interestPeriodId' => p.Id, 'baseRatePct' => 4.25, 'calculate' => true });
            Assert.areEqual('Calculated', rate.get('status'));
            Assert.isNotNull(rate.get('interestAmount'));

            Assert.areEqual(404, post('unknown', new Map<String, Object>()).get('httpStatus'));
            Assert.areEqual(400, post('drawdowns', new Map<String, Object>{ 'facilityId' => s.facility.Id, 'amount' => -1, 'valueDate' => String.valueOf(Date.today()) }).get('httpStatus'));
        }
    }

    @IsTest
    static void restApiForbiddenWithoutPermission() {
        Assert.areEqual(403, post('drawdowns', new Map<String, Object>()).get('httpStatus'));
    }
}
