import { createElement } from "lwc";
import ReceiveReturnGoods from "c/receiveReturnGoods";
import { getRecord, notifyRecordUpdateAvailable } from "lightning/uiRecordApi";
import receiveGoods from "@salesforce/apex/ReturnRequestController.receiveGoods";
jest.mock(
  "@salesforce/apex/ReturnRequestController.receiveGoods",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
const ShowToastEventName = "lightning__showtoast";

jest.mock(
  "lightning/actions",
  () => ({
    CloseActionScreenEvent: class extends CustomEvent {
      constructor() {
        super("lightning__actionsclosescreen");
      }
    }
  }),
  { virtual: true }
);

jest.mock(
  "@salesforce/label/c.SmartReturn_MSG_13",
  () => ({
    default: "Yêu cầu {0} vừa được người khác cập nhật. Vui lòng tải lại."
  }),
  { virtual: true }
);

const RECORD_ID = "a01000000000001AAA";
const MODIFIED = "2026-10-30T10:00:00.000Z";
const flush = async () => {
  await Promise.resolve();
  await Promise.resolve();
};

async function mount(status = "AWAITING_GOODS", myStore = true) {
  const element = createElement("c-receive-return-goods", {
    is: ReceiveReturnGoods
  });
  element.recordId = RECORD_ID;
  document.body.appendChild(element);
  getRecord.emit({
    apiName: "Return_Request__c",
    id: RECORD_ID,
    fields: {
      Name: { value: "RR-2610-00001" },
      Status__c: { value: status },
      Is_My_Store__c: { value: myStore },
      LastModifiedDate: { value: MODIFIED }
    }
  });
  await flush();
  return element;
}

const confirm = (element) =>
  element.shadowRoot.querySelectorAll("lightning-button")[1];

describe("c-receive-return-goods", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("confirms receipt only after persistence and sends the version read from LDS", async () => {
    let resolveSave;
    receiveGoods.mockImplementation(
      () =>
        new Promise((resolve) => {
          resolveSave = resolve;
        })
    );
    notifyRecordUpdateAvailable.mockResolvedValue(undefined);
    const element = await mount();
    const toast = jest.fn();
    const close = jest.fn();
    element.addEventListener(ShowToastEventName, toast);
    element.addEventListener("lightning__actionsclosescreen", close);

    expect(element.shadowRoot.textContent).toContain("RR-2610-00001");
    confirm(element).click();
    await flush();
    expect(receiveGoods).toHaveBeenCalledWith({
      requestId: RECORD_ID,
      lastModifiedAt: MODIFIED
    });
    expect(confirm(element).disabled).toBe(true);
    expect(toast).not.toHaveBeenCalled();
    expect(close).not.toHaveBeenCalled();

    resolveSave({ id: RECORD_ID });
    await flush();
    expect(toast.mock.calls[0][0].detail.variant).toBe("success");
    expect(close).toHaveBeenCalledTimes(1);
  });

  it.each([
    ["INSPECTING", true],
    ["COMPLETED", true],
    ["AWAITING_GOODS", false]
  ])(
    "does not receive goods for status %s with store membership %s",
    async (status, myStore) => {
      const element = await mount(status, myStore);
      expect(confirm(element).disabled).toBe(true);
      confirm(element).click();
      expect(receiveGoods).not.toHaveBeenCalled();
      expect(
        element.shadowRoot.querySelector('[role="status"]')
      ).not.toBeNull();
    }
  );

  it("keeps the dialog open and explains a conflicting update", async () => {
    receiveGoods.mockRejectedValue({
      body: {
        message:
          "Yêu cầu RR-2610-00001 vừa được người khác cập nhật. Vui lòng tải lại."
      }
    });
    const element = await mount();
    const close = jest.fn();
    element.addEventListener("lightning__actionsclosescreen", close);
    confirm(element).click();
    await flush();
    expect(element.shadowRoot.querySelector('[role="alert"]').textContent).toBe(
      "Yêu cầu RR-2610-00001 vừa được người khác cập nhật. Vui lòng tải lại."
    );
    expect(close).not.toHaveBeenCalled();
  });

  it("displays the save error without reporting success", async () => {
    receiveGoods.mockRejectedValue({
      body: { message: "Không có quyền cập nhật." }
    });
    const element = await mount();
    const toast = jest.fn();
    element.addEventListener(ShowToastEventName, toast);
    confirm(element).click();
    await flush();
    expect(
      element.shadowRoot.querySelector('[role="alert"]').textContent
    ).toContain("Không có quyền cập nhật.");
    expect(toast).not.toHaveBeenCalled();
  });

  it("preserves MSG-20 from the status field validation", async () => {
    const message = "Không thể chuyển yêu cầu từ CANCELLED sang INSPECTING.";
    receiveGoods.mockRejectedValue({
      body: {
        message: "An error occurred while trying to update the record.",
        output: { fieldErrors: { Status__c: [{ message }] } }
      }
    });
    const element = await mount();
    confirm(element).click();
    await flush();
    expect(element.shadowRoot.querySelector('[role="alert"]').textContent).toBe(
      message
    );
  });

  it("prevents confirmation if the record cannot be loaded", async () => {
    const element = await mount();
    getRecord.error();
    await flush();
    expect(confirm(element).disabled).toBe(true);
    expect(element.shadowRoot.querySelector('[role="alert"]')).not.toBeNull();
    expect(element.shadowRoot.querySelector("lightning-spinner")).toBeNull();
  });
});
