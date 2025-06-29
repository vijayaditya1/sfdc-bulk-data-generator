import { LightningElement, wire } from 'lwc';
import getObjects from '@salesforce/apex/MockDataController.getObjects';
import getObjectFields from '@salesforce/apex/MockDataController.getObjectFields';
import generateMockRecords from '@salesforce/apex/MockDataController.generateMockRecords';
import checkJobStatus from '@salesforce/apex/MockDataController.checkJobStatus';
import Toast from 'lightning/toast';

export default class MockData extends LightningElement {
    objectOptions;
    selectedObject = 'Account';
    fields = [];
    selectedFields = [];
    recordCount = 1000;
    isLoading = false;
    jobId = null;
    showFieldSelection = false;

    percentage;

    @wire(getObjects)
    wiredObjects({ error, data }) {
        if (data) {
            debugger;
            this.objectOptions = Object.keys(data).map(obj => ({
                label: data[obj],
                value: obj
            }));
        } else if (error) {
            this.showToast('Error', error.body.message, 'error');
        }
    }

    // Handle object selection
    handleObjectChange(event) {
        this.selectedObject = event.detail.value;
        this.showFieldSelection = true;
        this.fields = [];
        this.selectedFields = [];
    }

    // Load fields for selected object
    @wire(getObjectFields, { objectName: '$selectedObject' })
    wiredFields({ error, data }) {
        if (data) {
            this.fields = data.map(field => ({
                label: field.label,
                value: field.value
            }));
        } else if (error) {
            this.showToast('Error', error.body.message, 'error');
        }
    }

    // Handle field selection
    handleFieldChange(event) {
        this.selectedFields = event.detail.value;
    }

    // Handle record count change
    handleRecordCountChange(event) {
        this.recordCount = parseInt(event.target.value);
    }

    // Generate records
    async handleGenerate() {
        if (!this.selectedObject || this.selectedFields.length === 0) {
            this.showToast('Error', 'Please select an object and at least one field', 'error');
            return;
        }

        if (this.recordCount < 1 || this.recordCount > 4000000) {
            this.showToast('Error', 'Record count must be between 1 and 4,000,000', 'error');
            return;
        }

        this.isLoading = true;
        this.percentage = 1;
        try {
            this.jobId = await generateMockRecords({
                objectName: this.selectedObject,
                selectedFields: this.selectedFields,
                recordCount: this.recordCount
            });
            this.showToast('Success', 'Bulk job created. Job ID: ' + this.jobId, 'success');
            this.checkJobProgress();
        } catch (error) {
            this.showToast('Error', error.body.message, 'error');
            this.isLoading = false;
        }
    }

    // Poll job status
    checkJobProgress() {
        const interval = setInterval(async () => {
            try {
                const status = await checkJobStatus({ jobId: this.jobId });
                console.log(JSON.stringify(status));
                if (status.Status == 'Completed' || status.state === 'Failed' || status.state === 'Aborted') {
                    clearInterval(interval);
                    this.isLoading = false;
                    this.percentage = (status.JobItemsProcessed * 100) / status.TotalJobItems;
                    this.showToast(
                        status.Status === 'Completed' ? 'Success' : 'Error',
                        `Records processed`,
                        status.Status === 'Completed' ? 'success' : 'error'
                    );
                } else {
                    this.percentage = (status.JobItemsProcessed * 100) / status.TotalJobItems;
                }
            } catch (error) {
                clearInterval(interval);
                this.isLoading = false;
                this.showToast('Error', error.body.message, 'error');
            }
        }, 5000);
    }

    // Show toast notification
    showToast(label, message, variant) {
        Toast.show({ label, message, variant }, this);
    }
}