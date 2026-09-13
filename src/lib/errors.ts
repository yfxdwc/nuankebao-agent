// ============================================
// 全局错误处理 + 结构化日志
// W10 Phase 2 优化
//
// 借鉴 Sentry / OpenTelemetry 设计
// ============================================

export type LogLevel = "debug" | "info" | "warn" | "error";

export interface LogContext {
  // 用户上下文
  userId?: string;
  // 请求上下文
  requestId?: string;
  method?: string;
  path?: string;
  ip?: string;
  // 业务上下文
  customerId?: string;
  endpoint?: string;
  // 任意扩展
  [key: string]: unknown;
}

const LEVELS: Record<LogLevel, number> = {
  debug: 10,
  info: 20,
  warn: 30,
  error: 40,
};

const MIN_LEVEL: LogLevel = (process.env.LOG_LEVEL as LogLevel) || "info";

function shouldLog(level: LogLevel): boolean {
  return LEVELS[level] >= LEVELS[MIN_LEVEL];
}

function format(level: LogLevel, msg: string, context?: LogContext, err?: unknown) {
  const entry = {
    timestamp: new Date().toISOString(),
    level,
    msg,
    ...context,
    error: err
      ? {
          message: err instanceof Error ? err.message : String(err),
          stack: err instanceof Error ? err.stack : undefined,
        }
      : undefined,
  };
  return JSON.stringify(entry);
}

export const logger = {
  debug(msg: string, context?: LogContext) {
    if (shouldLog("debug")) console.debug(format("debug", msg, context));
  },
  info(msg: string, context?: LogContext) {
    if (shouldLog("info")) console.info(format("info", msg, context));
  },
  warn(msg: string, context?: LogContext, err?: unknown) {
    if (shouldLog("warn")) console.warn(format("warn", msg, context, err));
  },
  error(msg: string, context?: LogContext, err?: unknown) {
    if (shouldLog("error")) console.error(format("error", msg, context, err));
  },
};

/**
 * Next.js Route Handler 错误包装
 * 统一处理 try/catch + 错误响应
 */
export class HttpError extends Error {
  constructor(
    public statusCode: number,
    public override message: string,
    public details?: unknown
  ) {
    super(message);
    this.name = "HttpError";
  }
}

export const httpErrors = {
  badRequest: (msg: string, details?: unknown) =>
    new HttpError(400, msg, details),
  unauthorized: (msg = "Unauthorized") => new HttpError(401, msg),
  forbidden: (msg = "Forbidden") => new HttpError(403, msg),
  notFound: (msg = "Not found") => new HttpError(404, msg),
  tooManyRequests: (msg = "Too many requests") => new HttpError(429, msg),
  internal: (msg = "Internal server error") => new HttpError(500, msg),
};

/**
 * Route Handler 统一错误响应
 */
export function errorResponse(err: unknown): Response {
  if (err instanceof HttpError) {
    return Response.json(
      { error: err.message, ...(err.details ? { details: err.details } : {}) },
      { status: err.statusCode }
    );
  }

  if (err && typeof err === "object" && "name" in err && (err as { name: string }).name === "ZodError") {
    const zodErr = err as { errors?: unknown; issues?: unknown };
    return Response.json(
      { error: "Invalid input", details: zodErr.errors ?? zodErr.issues },
      { status: 400 }
    );
  }

  // 未知错误, 500
  logger.error("Unhandled error in route", {}, err);
  return Response.json({ error: "Internal server error" }, { status: 500 });
}

// (zodErrorLike 抽到上面了)