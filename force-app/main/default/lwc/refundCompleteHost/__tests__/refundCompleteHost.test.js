import { createElement } from "lwc";
import RefundCompleteHost from "c/refundCompleteHost";
import { getRecord, notifyRecordUpdateAvailable } from "lightning/uiRecordApi";
import { subscribe } from "lightning/messageService";
import manualComplete from "@salesforce/apex/RefundService.manualComplete";

jest.mock(
  "@salesforce/apex/RefundService.manualComplete",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/customPermission/Refund_Manual_Complete",
  () => ({ default: true }),
  { virtual: true }
);
const REFUND_ID = "a01000000000001AAA";
const REQUEST_ID = "a02000000000001AAA";

function refund(manualAt = null, requestStatus = "REFUND_FAILED") {
  return {
    apiName: "Refund_Transaction__c",
    id: REFUND_ID,
    fields: {
      Name: { value: "RFT-000001" },
      Status__c: { value: "FAILED" },
      Refund_Amount__c: { value: 25000000 },
      Return_Request__c: { value: REQUEST_ID },
      Merchant_Reference__c: { value: "RR-2610-00015" },
      Order_Number__c: { value: "00012345" },
      Return_Request__r: {
        value: { fields: { Status__c: { value: requestStatus } } }
      },
      Manual_Completed_At__c: { value: manualAt },
      Manual_Reference__c: { value: manualAt ? "BANK-123" : null },
      Last_Error_Code__c: { value: "RETRY_EXHAUSTED" },
      Last_Error_Message__c: { value: "PayHub did not respond" }
    }
  };
}

async function flush() {
  await Promise.resolve();
  await Promise.resolve();
}

function completeButton(element) {
  return Array.from(
    element.shadowRoot.querySelectorAll("lightning-button")
  ).find((button) => button.label === "Confirm");
}

describe("c-refund-complete-host", () => {
  afterEach(() => {
    while (document.body.firstChild)
      document.body.removeChild(document.body.firstChild);
    jest.clearAllMocks();
  });

  async function mount(requestStatus = "REFUND_FAILED", manualAt = null) {
    const element = createElement("c-refund-complete-host", {
      is: RefundCompleteHost
    });
    element.recordId = REFUND_ID;
    document.body.appendChild(element);
    getRecord.emit(refund(manualAt, requestStatus));
    await flush();
    subscribe.mock.calls[0][2]({ recordId: REFUND_ID });
    await flush();
    return element;
  }

  it("puts refund amount, business references, and failure ahead of confirmation", async () => {
    const element = await mount();
    const content = element.shadowRoot.textContent;

    expect(content).toContain("Refund failed");
    expect(content).toContain("RFT-000001");
    expect(content).toContain("RR-2610-00015");
    expect(content).toContain("00012345");
    expect(content).toContain("RETRY_EXHAUSTED");
    expect(element.shadowRoot.querySelectorAll('[role="dialog"]')).toHaveLength(
      1
    );
    expect(
      element.shadowRoot.querySelector(".dialog-header h2").textContent
    ).toContain("Complete Refund");
    expect(
      element.shadowRoot
        .querySelector(".dialog-close")
        .getAttribute("aria-label")
    ).toBe("Close");
    expect(
      element.shadowRoot.querySelector("lightning-formatted-number").value
    ).toBe(25000000);
    expect(element.shadowRoot.querySelectorAll("lightning-input")).toHaveLength(
      2
    );
  });

  it("requires both reference and explicit reconciliation confirmation", async () => {
    const element = await mount();
    const button = completeButton(element);
    expect(button.disabled).toBe(true);

    const reference = element.shadowRoot.querySelectorAll("lightning-input")[0];
    reference.value = "BANK-123";
    reference.dispatchEvent(new CustomEvent("change"));
    await flush();
    expect(button.disabled).toBe(true);

    const confirmation =
      element.shadowRoot.querySelectorAll("lightning-input")[1];
    confirmation.checked = true;
    confirmation.dispatchEvent(new CustomEvent("change"));
    await flush();
    expect(button.disabled).toBe(false);
  });

  it("hides manual completion when the request has already completed", async () => {
    const element = await mount("COMPLETED", "2026-10-23T10:00:00.000Z");
    expect(completeButton(element)).toBeUndefined();
    expect(element.shadowRoot.textContent).toContain(
      "Manual completion recorded"
    );
  });

  it("shows success only after the saved refund and request states are reloaded", async () => {
    manualComplete.mockResolvedValue(undefined);
    notifyRecordUpdateAvailable.mockResolvedValue(undefined);
    const element = await mount();
    const reference = element.shadowRoot.querySelectorAll("lightning-input")[0];
    reference.value = "BANK-123";
    reference.dispatchEvent(new CustomEvent("change"));
    const confirmation =
      element.shadowRoot.querySelectorAll("lightning-input")[1];
    confirmation.checked = true;
    confirmation.dispatchEvent(new CustomEvent("change"));
    await flush();

    completeButton(element).click();
    await flush();
    expect(manualComplete).toHaveBeenCalledWith({
      refundId: REFUND_ID,
      externalReference: "BANK-123"
    });
    expect(element.shadowRoot.textContent).not.toContain(
      "Manual completion recorded"
    );
    expect(element.shadowRoot.textContent).toContain("Verifying saved status");

    getRecord.emit(refund("2026-10-23T10:00:00.000Z", "COMPLETED"));
    await flush();
    expect(element.shadowRoot.textContent).toContain(
      "Manual completion recorded"
    );
  });

  it("keeps the record unconfirmed if server validation fails", async () => {
    manualComplete.mockRejectedValue({
      body: { message: "Only a failed refund can be completed manually." }
    });
    const element = await mount();
    const reference = element.shadowRoot.querySelectorAll("lightning-input")[0];
    reference.value = "BANK-123";
    reference.dispatchEvent(new CustomEvent("change"));
    const confirmation =
      element.shadowRoot.querySelectorAll("lightning-input")[1];
    confirmation.checked = true;
    confirmation.dispatchEvent(new CustomEvent("change"));
    await flush();

    completeButton(element).click();
    await flush();
    expect(element.shadowRoot.textContent).toContain(
      "The refund status has changed"
    );
    expect(element.shadowRoot.textContent).not.toContain(
      "Manual completion recorded"
    );
  });
});
