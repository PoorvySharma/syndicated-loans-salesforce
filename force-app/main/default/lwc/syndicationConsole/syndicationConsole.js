import { LightningElement, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getDeals from '@salesforce/apex/SyndicationConsoleController.getDeals';
import getBoard from '@salesforce/apex/SyndicationConsoleController.getBoard';
import perform from '@salesforce/apex/SyndicationConsoleController.perform';

const money = { minimumFractionDigits: 2 };

export default class SyndicationConsole extends LightningElement {
    dealId;
    deal;
    facilities = [];
    isLoading = false;
    baseRate;
    amount;
    valueDate;
    dealOptions = [];

    @wire(getDeals)
    wiredDeals({ data }) {
        if (data) {
            this.dealOptions = data.map((d) => ({ label: `${d.Name} (${d.Stage__c})`, value: d.Id }));
        }
    }

    get borrowerName() {
        return this.deal?.Borrower__r?.Name ?? '-';
    }
    get agentName() {
        return this.deal?.Agent__r?.Name ?? '-';
    }
    get cpText() {
        return this.deal?.CPs_Satisfied__c ? 'Yes' : 'No';
    }

    lenderColumns = [
        { label: 'Lender', fieldName: 'LenderName' },
        { label: 'Status', fieldName: 'Status__c' },
        { label: 'Soft commit', fieldName: 'Soft_Commit_Amount__c', type: 'currency', typeAttributes: money },
        { label: 'Allocated', fieldName: 'Allocated_Amount__c', type: 'currency', typeAttributes: money },
        { label: 'Share %', fieldName: 'Share_Pct__c', type: 'number', typeAttributes: money },
        { label: 'Funded', fieldName: 'Funded_Amount__c', type: 'currency', typeAttributes: money }
    ];

    drawdownColumns = [
        { label: 'Drawdown', fieldName: 'Name' },
        { label: 'Amount', fieldName: 'Amount__c', type: 'currency', typeAttributes: money },
        { label: 'Value date', fieldName: 'Value_Date__c', type: 'date-local' },
        { label: 'Status', fieldName: 'Status__c' },
        { label: 'Note', fieldName: 'Rejection_Reason__c' },
        { type: 'action', typeAttributes: { rowActions: this.drawdownActions.bind(this) } }
    ];

    periodColumns = [
        { label: 'Period', fieldName: 'Name' },
        { label: 'Drawdown', fieldName: 'DrawdownName' },
        { label: 'Start', fieldName: 'Start_Date__c', type: 'date-local' },
        { label: 'End', fieldName: 'End_Date__c', type: 'date-local' },
        { label: 'Base %', fieldName: 'Base_Rate_Pct__c', type: 'number', typeAttributes: { minimumFractionDigits: 4 } },
        { label: 'All-in %', fieldName: 'All_In_Rate_Pct__c', type: 'number', typeAttributes: { minimumFractionDigits: 4 } },
        { label: 'Interest', fieldName: 'Interest_Amount__c', type: 'currency', typeAttributes: money },
        { label: 'Status', fieldName: 'Status__c' },
        { type: 'action', typeAttributes: { rowActions: this.periodActions.bind(this) } }
    ];

    drawdownActions(row, done) {
        const byStatus = {
            Requested: [{ label: 'Validate & notify lenders', name: 'NOTIFY_DRAWDOWN' }],
            Notified: [{ label: 'Confirm funding', name: 'FUND_DRAWDOWN' }],
            Funded: [
                { label: 'Open interest period', name: 'OPEN_PERIOD' },
                { label: 'Repay', name: 'REPAY_DRAWDOWN' }
            ]
        };
        done(byStatus[row.Status__c] || []);
    }

    periodActions(row, done) {
        const byStatus = {
            Open: [{ label: 'Fix rate', name: 'FIX_RATE' }],
            'Rate Fixed': [{ label: 'Calculate interest', name: 'CALC_INTEREST' }],
            Calculated: [{ label: 'Mark paid', name: 'MARK_PAID' }],
            Paid: [{ label: 'Distribute to lenders', name: 'DISTRIBUTE' }]
        };
        done(byStatus[row.Status__c] || []);
    }

    handleDeal(event) {
        this.dealId = event.detail.value;
        this.refresh();
    }

    handleInput(event) {
        this[event.target.dataset.field] = event.target.value;
    }

    async refresh() {
        if (!this.dealId) {
            return;
        }
        this.isLoading = true;
        try {
            await this.load();
        } catch (e) {
            this.toast('Could not load deal', this.errText(e), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async load() {
        const b = await getBoard({ dealId: this.dealId });
        this.deal = b.deal;
        this.facilities = (b.facilities || []).map((f) => this.toView(f));
    }

    toView(f) {
        const lenders = (f.Lender_Commitments__r || []).map((l) => ({ ...l, LenderName: l.Lender__r ? l.Lender__r.Name : '' }));
        const drawdowns = f.Drawdowns__r || [];
        const periods = [];
        drawdowns.forEach((d) => (d.Interest_Periods__r || []).forEach((p) => periods.push({ ...p, DrawdownName: d.Name })));
        const fmt = (v) => (v === undefined || v === null ? '-' : Number(v).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 }));
        return {
            ...f,
            lenders,
            drawdowns,
            periods,
            hasPeriods: periods.length > 0,
            disableAllocate: ['Active', 'Repaid', 'Cancelled'].includes(f.Status__c),
            disableClose: f.Status__c !== 'Allocated',
            metrics: [
                { label: 'Commitment', value: fmt(f.Commitment_Amount__c) },
                { label: 'Soft commitments', value: `${fmt(f.Soft_Commit_Total__c)} (${f.Oversubscription__c ?? 0}x)` },
                { label: 'Allocated', value: fmt(f.Allocated_Amount__c) },
                { label: 'Drawn', value: fmt(f.Drawn_Amount__c) },
                { label: 'Pending', value: fmt(f.Pending_Amount__c) },
                { label: 'Available', value: fmt(f.Available_Amount__c) }
            ]
        };
    }

    handleAllocate(event) {
        this.run('ALLOCATE', event.target.dataset.id);
    }
    handleClose(event) {
        this.run('CLOSE_FACILITY', event.target.dataset.id);
    }
    handleRequestDrawdown(event) {
        this.run('REQUEST_DRAWDOWN', event.target.dataset.id, this.amount ? Number(this.amount) : null, this.valueDate || null);
    }
    handleRowAction(event) {
        const action = event.detail.action.name;
        const rate = action === 'FIX_RATE' && this.baseRate !== undefined && this.baseRate !== '' ? Number(this.baseRate) : null;
        this.run(action, event.detail.row.Id, rate);
    }

    async run(action, recordId, numberArg = null, dateArg = null) {
        this.isLoading = true;
        try {
            const msg = await perform({ action, recordId, numberArg, dateArg });
            this.toast('Done', msg, 'success');
            await this.load();
        } catch (e) {
            this.toast('Action failed', this.errText(e), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    errText(e) {
        return (e && e.body && e.body.message) || (e && e.message) || 'Unknown error';
    }
    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
