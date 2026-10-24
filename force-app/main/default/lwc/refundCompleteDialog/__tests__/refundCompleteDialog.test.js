import { createElement } from "lwc";
import { publish } from "lightning/messageService";
import COMPLETE_REFUND_CHANNEL from "@salesforce/messageChannel/Refund_Complete__c";
import RefundCompleteDialog from "c/refundCompleteDialog";

it("opens the matching refund dialog from the record action", async () => {
  const element = createElement("c-refund-complete-dialog", {
    is: RefundCompleteDialog
  });
  element.recordId = "a01000000000001AAA";
  document.body.appendChild(element);
  await Promise.resolve();

  element.invoke();

  expect(publish).toHaveBeenCalledWith(undefined, COMPLETE_REFUND_CHANNEL, {
    recordId: "a01000000000001AAA"
  });
  document.body.removeChild(element);
});
