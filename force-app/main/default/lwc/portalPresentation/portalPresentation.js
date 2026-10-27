const STATUSES = {
  CREATED: "Đã tạo yêu cầu",
  NEW: "Mới tạo",
  PENDING_APPROVAL: "Chờ phê duyệt",
  AWAITING_GOODS: "Chờ nhận hàng",
  INSPECTING: "Đang kiểm định",
  RE_CONFIRMING: "Chờ duyệt lại",
  REFUND_PROCESSING: "Đang xử lý hoàn tiền",
  COMPLETED: "Đã hoàn tiền",
  REFUND_FAILED: "Hoàn tiền chưa thành công",
  REJECTED: "Đã từ chối",
  CANCELLED: "Đã hủy"
};

export function statusLabel(status) {
  return STATUSES[status] || "Trạng thái đang cập nhật";
}

export function amountLabel(request) {
  if (request.amountKind !== "ACTUAL") return "Số tiền hoàn dự kiến";
  return request.status === "COMPLETED"
    ? "Số tiền đã hoàn"
    : "Số tiền hoàn thực tế";
}
