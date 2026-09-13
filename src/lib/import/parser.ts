import * as XLSX from "xlsx";

// ============================================
// Excel/CSV 解析器
// 支持 .xlsx / .xls / .csv
// ============================================

export interface ParsedRow {
  rowNumber: number;
  data: Record<string, unknown>;
  errors: string[];
}

export interface ParsedFile {
  rows: ParsedRow[];
  totalRows: number;
  validRows: number;
  invalidRows: number;
  headers: string[];
}

/**
 * 解析上传的 Excel/CSV Buffer
 */
export function parseImportFile(buffer: ArrayBuffer): ParsedFile {
  const workbook = XLSX.read(buffer, { type: "array" });
  const sheetName = workbook.SheetNames[0];
  if (!sheetName) {
    throw new Error("文件没有 sheet");
  }
  const sheet = workbook.Sheets[sheetName];

  // 转成 JSON (header 用第一行)
  const json = XLSX.utils.sheet_to_json<Record<string, unknown>>(sheet, {
    defval: "",
    raw: false,
  });

  if (json.length === 0) {
    throw new Error("文件为空");
  }

  // headers = 第一行的所有 key
  const headers = Object.keys(json[0] ?? {});

  const rows: ParsedRow[] = json.map((data, idx) => ({
    rowNumber: idx + 2, // Excel 第 1 行是 header, 数据从第 2 行起
    data,
    errors: [],
  }));

  return {
    rows,
    totalRows: rows.length,
    validRows: rows.length,
    invalidRows: 0,
    headers,
  };
}

/**
 * 生成 Excel 模板 (客户导入用)
 */
export function generateTemplate(): ArrayBuffer {
  const headers = [
    "姓名",
    "手机号",
    "性别",
    "出生年",
    "健康标签",
    "既往病史",
    "备注",
  ];

  const examples = [
    {
      姓名: "张三",
      手机号: "13800138000",
      性别: "男",
      出生年: 1985,
      健康标签: "肩颈,睡眠差",
      既往病史: "无",
      备注: "VIP 客户",
    },
    {
      姓名: "李四",
      手机号: "13900139000",
      性别: "女",
      出生年: 1990,
      健康标签: "腰部,体寒",
      既往病史: "高血压",
      备注: "",
    },
  ];

  const ws = XLSX.utils.json_to_sheet(examples, { header: headers });
  const wb = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(wb, ws, "客户列表");

  // 设置列宽
  ws["!cols"] = [
    { wch: 10 }, // 姓名
    { wch: 14 }, // 手机号
    { wch: 8 },  // 性别
    { wch: 8 },  // 出生年
    { wch: 20 }, // 健康标签
    { wch: 30 }, // 既往病史
    { wch: 30 }, // 备注
  ];

  return XLSX.write(wb, { type: "array", bookType: "xlsx" });
}