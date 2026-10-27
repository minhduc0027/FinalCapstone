import { createElement } from "lwc";
import MyReturnRequests from "c/myReturnRequests";
import listRequests from "@salesforce/apex/ReturnPortalController.listRequests";
import getRequest from "@salesforce/apex/ReturnPortalController.getRequest";

jest.mock("@salesforce/user/isGuest", () => ({ default: false }), {
  virtual: true
});
jest.mock(
  "@salesforce/apex/ReturnPortalController.listRequests",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ReturnPortalController.getRequest",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

const flush = async () => {
  await Promise.resolve();
  await Promise.resolve();
};
function render() {
  const element = createElement("c-my-return-requests", {
    is: MyReturnRequests
  });
  document.body.appendChild(element);
  return element;
}

describe("my return requests", () => {
  afterEach(() => {
    document.body.replaceChildren();
  });

  it("shows a meaningful empty state", async () => {
    const element = render();
    listRequests.emit({ requests: [], hasNext: false });
    await flush();
    expect(element.shadowRoot.textContent).toContain(
      "Bạn chưa có yêu cầu đổi trả nào"
    );
  });

  it("opens a read-only detail by request number", async () => {
    const element = render();
    const request = {
      requestNumber: "RR-2610-00001",
      status: "NEW",
      refundAmount: 2490000,
      amountKind: "ESTIMATED",
      lines: [],
      history: []
    };
    listRequests.emit({ requests: [request], hasNext: false });
    await flush();
    element.shadowRoot.querySelector('[data-number="RR-2610-00001"]').click();
    await flush();
    expect(getRequest.getLastConfig()).toEqual({
      requestNumber: "RR-2610-00001"
    });
    getRequest.emit(request);
    await flush();
    const detail = element.shadowRoot.querySelector("c-return-request-summary");
    expect(detail.showAmount).toBe(true);
    expect(detail.request.requestNumber).toBe(request.requestNumber);
    expect(
      element.shadowRoot.querySelector("lightning-record-edit-form")
    ).toBeNull();
  });

  it("caps Builder page size before requesting a page", async () => {
    const element = render();
    element.pageSize = 500;
    await flush();
    expect(listRequests.getLastConfig().pageSize).toBe(50);
  });
});
