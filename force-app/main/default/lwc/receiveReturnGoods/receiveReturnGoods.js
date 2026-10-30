import { LightningElement, api, wire } from "lwc";
import {
  getRecord,
  getFieldValue,
  notifyRecordUpdateAvailable
} from "lightning/uiRecordApi";
import { CloseActionScreenEvent } from "lightning/actions";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { RefreshEvent } from "lightning/refresh";
import STATUS from "@salesforce/schema/Return_Request__c.Status__c";
import MY_STORE from "@salesforce/schema/Return_Request__c.Is_My_Store__c";
import MODIFIED from "@salesforce/schema/Return_Request__c.LastModifiedDate";
import receiveGoods from "@salesforce/apex/ReturnRequestController.receiveGoods";
import NAME from "@salesforce/schema/Return_Request__c.Name";

export default class ReceiveReturnGoods extends LightningElement {
  @api recordId;
  request;
  error;
  saving = false;

  @wire(getRecord, {
    recordId: "$recordId",
    fields: [STATUS, MY_STORE, MODIFIED, NAME]
  })
  wiredRequest({ data, error }) {
    if (data) {
      this.request = data;
      this.error = undefined;
    } else if (error) {
      this.request = undefined;
      this.error =
        "Không thể tải yêu cầu. Hãy kiểm tra quyền truy cập và tải lại trang.";
    }
  }

  get loading() {
    return (!this.request && !this.error) || this.saving;
  }

  get name() {
    return getFieldValue(this.request, NAME);
  }

  get canReceive() {
    return (
      getFieldValue(this.request, STATUS) === "AWAITING_GOODS" &&
      getFieldValue(this.request, MY_STORE) === true
    );
  }

  get unavailable() {
    return this.request && !this.canReceive;
  }

  get disabled() {
    return !this.canReceive || this.saving;
  }

  handleCancel() {
    this.dispatchEvent(new CloseActionScreenEvent());
  }

  async handleReceive() {
    if (this.disabled) return;

    this.saving = true;
    this.error = undefined;
    try {
      await receiveGoods({
        requestId: this.recordId,
        lastModifiedAt: getFieldValue(this.request, MODIFIED)
      });
      await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Đã nhận hàng",
          message: "Yêu cầu đã chuyển sang đang kiểm định.",
          variant: "success"
        })
      );
      this.dispatchEvent(new RefreshEvent());
      this.dispatchEvent(new CloseActionScreenEvent());
    } catch (error) {
      this.error =
        error.body?.output?.fieldErrors?.[STATUS.fieldApiName]?.[0]?.message ||
        error.body?.output?.errors?.[0]?.message ||
        error.body?.message ||
        error.message ||
        "Không thể xác nhận nhận hàng. Hãy thử lại.";
    } finally {
      this.saving = false;
    }
  }
}
