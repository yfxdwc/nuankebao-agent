import type { Config } from "tailwindcss";
import animate from "tailwindcss-animate";

// ============================================
// 暖客宝 Tailwind 配置
// ============================================
//
// ⚠ 语义色的**真源**是 design/tokens/design-tokens.json, 不是这里。
//   这里只做「CSS 变量 → Tailwind 类名」的映射, 不含任何字面色值。
//   改颜色 → 改 design-tokens.json → `pnpm tokens:build` (会同时生成 globals.css + Flutter token)
//
// 三层命名:
//   1) shadcn/ui 兼容层 (border/bg-primary/text-muted-foreground …) —— 存量 600+ 处用法, 不要删
//   2) 新语义层 (bg-brand / text-success / border-default / bg-surface-subtle …) —— 新代码优先用这个
//   3) 尺度层 (p-card / gap-section / text-body / rounded-card / shadow-md) —— 收紧/放松全站密度
//
const config: Config = {
  darkMode: ["class"],
  content: ["./src/**/*.{ts,tsx}"],
  theme: {
    container: {
      center: true,
      padding: "2rem",
      screens: { "2xl": "1400px" },
    },
    extend: {
      colors: {
        // ---- 1) shadcn/ui 兼容层 ----
        border: "rgb(var(--border-rgb) / <alpha-value>)",
        input: "rgb(var(--input-rgb) / <alpha-value>)",
        ring: "rgb(var(--ring-rgb) / <alpha-value>)",
        background: "rgb(var(--background-rgb) / <alpha-value>)",
        foreground: "rgb(var(--foreground-rgb) / <alpha-value>)",
        primary: {
          DEFAULT: "rgb(var(--primary-rgb) / <alpha-value>)",
          foreground: "rgb(var(--primary-foreground-rgb) / <alpha-value>)",
        },
        secondary: {
          DEFAULT: "rgb(var(--secondary-rgb) / <alpha-value>)",
          foreground: "rgb(var(--secondary-foreground-rgb) / <alpha-value>)",
        },
        destructive: {
          DEFAULT: "rgb(var(--destructive-rgb) / <alpha-value>)",
          foreground: "rgb(var(--destructive-foreground-rgb) / <alpha-value>)",
        },
        muted: {
          DEFAULT: "rgb(var(--muted-rgb) / <alpha-value>)",
          foreground: "rgb(var(--muted-foreground-rgb) / <alpha-value>)",
        },
        accent: {
          DEFAULT: "rgb(var(--accent-rgb) / <alpha-value>)",
          foreground: "rgb(var(--accent-foreground-rgb) / <alpha-value>)",
        },
        card: {
          DEFAULT: "rgb(var(--card-rgb) / <alpha-value>)",
          foreground: "rgb(var(--card-foreground-rgb) / <alpha-value>)",
        },
        popover: {
          DEFAULT: "rgb(var(--popover-rgb) / <alpha-value>)",
          foreground: "rgb(var(--popover-foreground-rgb) / <alpha-value>)",
        },

        // ---- 2) 新语义层 ----
        brand: {
          DEFAULT: "rgb(var(--brand-rgb) / <alpha-value>)",
          light: "rgb(var(--brand-light-rgb) / <alpha-value>)",
          dark: "rgb(var(--brand-dark-rgb) / <alpha-value>)",
          surface: "rgb(var(--brand-surface-rgb) / <alpha-value>)",
          foreground: "rgb(var(--brand-foreground-rgb) / <alpha-value>)",
          accent: "rgb(var(--brand-accent-rgb) / <alpha-value>)",
          "accent-light": "rgb(var(--brand-accent-light-rgb) / <alpha-value>)",
          "accent-surface": "rgb(var(--brand-accent-surface-rgb) / <alpha-value>)",
          "accent-foreground": "rgb(var(--brand-accent-foreground-rgb) / <alpha-value>)",
        },
        surface: {
          DEFAULT: "rgb(var(--surface-rgb) / <alpha-value>)",
          card: "rgb(var(--surface-card-rgb) / <alpha-value>)",
          subtle: "rgb(var(--surface-subtle-rgb) / <alpha-value>)",
          sunken: "rgb(var(--surface-sunken-rgb) / <alpha-value>)",
          inverse: "rgb(var(--surface-inverse-rgb) / <alpha-value>)",
        },
        content: {
          // 命名成 content* 而不是 text*: 避免和 Tailwind 的 text-<size> 撞命名空间
          primary: "rgb(var(--text-primary-rgb) / <alpha-value>)",
          secondary: "rgb(var(--text-secondary-rgb) / <alpha-value>)",
          tertiary: "rgb(var(--text-tertiary-rgb) / <alpha-value>)",
          disabled: "rgb(var(--text-disabled-rgb) / <alpha-value>)",
          inverse: "rgb(var(--text-on-inverse-rgb) / <alpha-value>)",
        },
        success: {
          DEFAULT: "rgb(var(--success-rgb) / <alpha-value>)",
          light: "rgb(var(--success-light-rgb) / <alpha-value>)",
          surface: "rgb(var(--success-surface-rgb) / <alpha-value>)",
          foreground: "rgb(var(--success-foreground-rgb) / <alpha-value>)",
        },
        warning: {
          DEFAULT: "rgb(var(--warning-rgb) / <alpha-value>)",
          light: "rgb(var(--warning-light-rgb) / <alpha-value>)",
          surface: "rgb(var(--warning-surface-rgb) / <alpha-value>)",
          foreground: "rgb(var(--warning-foreground-rgb) / <alpha-value>)",
        },
        danger: {
          DEFAULT: "rgb(var(--danger-rgb) / <alpha-value>)",
          light: "rgb(var(--danger-light-rgb) / <alpha-value>)",
          surface: "rgb(var(--danger-surface-rgb) / <alpha-value>)",
          foreground: "rgb(var(--danger-foreground-rgb) / <alpha-value>)",
        },
        info: {
          DEFAULT: "rgb(var(--info-rgb) / <alpha-value>)",
          light: "rgb(var(--info-light-rgb) / <alpha-value>)",
          surface: "rgb(var(--info-surface-rgb) / <alpha-value>)",
          foreground: "rgb(var(--info-foreground-rgb) / <alpha-value>)",
        },
        divider: "rgb(var(--divider-rgb) / <alpha-value>)",
        "border-default": "rgb(var(--border-default-rgb) / <alpha-value>)",
        "border-strong": "rgb(var(--border-strong-rgb) / <alpha-value>)",
        gold: {
          DEFAULT: "rgb(var(--member-gold-rgb) / <alpha-value>)",
          surface: "rgb(var(--member-gold-surface-rgb) / <alpha-value>)",
        },
        neutral: {
          DEFAULT: "rgb(var(--badge-neutral-rgb) / <alpha-value>)",
          surface: "rgb(var(--badge-neutral-surface-rgb) / <alpha-value>)",
        },
        graph: {
          a: "rgb(var(--graph-a-rgb) / <alpha-value>)",
          "a-surface": "rgb(var(--graph-a-surface-rgb) / <alpha-value>)",
          b: "rgb(var(--graph-b-rgb) / <alpha-value>)",
          "b-surface": "rgb(var(--graph-b-surface-rgb) / <alpha-value>)",
          line: "rgb(var(--graph-line-rgb) / <alpha-value>)",
          "line-soft": "rgb(var(--graph-line-soft-rgb) / <alpha-value>)",
        },
        scrim: "rgb(var(--scrim-rgb) / <alpha-value>)",

        // ---- 图表色板 (recharts / 手写 SVG 共用) ----
        chart: {
          1: "rgb(var(--chart-1-rgb) / <alpha-value>)",
          2: "rgb(var(--chart-2-rgb) / <alpha-value>)",
          3: "rgb(var(--chart-3-rgb) / <alpha-value>)",
          4: "rgb(var(--chart-4-rgb) / <alpha-value>)",
          5: "rgb(var(--chart-5-rgb) / <alpha-value>)",
          6: "rgb(var(--chart-6-rgb) / <alpha-value>)",
        },
      },

      borderRadius: {
        // shadcn/ui 兼容层 —— 映射到生成的数值档位 (等价于原来的 calc(--radius ± 2px))
        lg: "var(--radius-8)",
        md: "var(--radius-6)",
        sm: "var(--radius-4)",
        // 语义别名
        card: "var(--radius-card)",
        chip: "var(--radius-chip)",
        badge: "var(--radius-badge)",
        sheet: "var(--radius-sheet)",
        dialog: "var(--radius-dialog)",
        pill: "var(--radius-pill)",
      },

      // 语义间距 —— 让「卡片内边距」这种概念可被一次调整
      spacing: {
        "card-x": "var(--space-card-padding)",
        "card-y": "var(--space-card-padding)",
        "section-y": "var(--space-section-gap)",
        "page-x": "var(--space-page-padding)",
        "inline": "var(--space-inline-gap)",
        "tight": "var(--space-tight-gap)",
        "row-y": "var(--space-list-row-padding)",
        "field-y": "var(--space-form-field-gap)",
      },

      // 交互控件高/宽 —— 把散落各处的 min-h-[44px] 这类收进令牌 (值不变, 但从此可一处调)
      minHeight: {
        "control-sm": "var(--size-control-sm)",
        control: "var(--size-control-md)",
        "control-lg": "var(--size-control-lg)",
        "tap-compact": "var(--size-tap-compact)",
        tap: "var(--size-tap-min)",
        field: "var(--size-button-min-height)",
        "field-lg": "var(--size-field-lg)",
        row: "var(--size-list-row-height)",
        textarea: "var(--size-textarea-min-height)",
      },
      minWidth: {
        "tap-compact": "var(--size-tap-compact)",
        tap: "var(--size-tap-min)",
        badge: "var(--size-badge-min-width)",
        "badge-lg": "var(--size-badge-min-width-lg)",
        table: "var(--size-table-min-width)",
      },
      maxWidth: { content: "var(--size-content-max-width)" },
      height: {
        "control-sm": "var(--size-control-sm)",
        control: "var(--size-control-md)",
        "control-lg": "var(--size-control-lg)",
        tap: "var(--size-tap-min)",
        fab: "var(--size-fab-size)",
      },
      width: {
        "control-sm": "var(--size-control-sm)",
        control: "var(--size-control-md)",
        tap: "var(--size-tap-min)",
        fab: "var(--size-fab-size)",
      },

      fontSize: {
        // xxs 仅限 web admin 密集区 (表格/角标); Flutter APK 可读性底线仍是 14px
        xxs: ["var(--text-xxs)", { lineHeight: "1.4" }],
        // 语义字号 (中老年: 正文 18px, 比 Tailwind 默认 16px 大一档)
        caption: ["var(--text-xs)", { lineHeight: "1.5" }],
        body: ["var(--text-sm)", { lineHeight: "1.6" }],
        "body-lg": ["var(--text-md)", { lineHeight: "1.6" }],
        "title-sm": ["var(--text-lg)", { lineHeight: "1.4" }],
        title: ["var(--text-xl)", { lineHeight: "1.3" }],
        display: ["var(--text-xxl)", { lineHeight: "1.2" }],
      },

      fontFamily: {
        sans: "var(--font-sans)",
        mono: "var(--font-mono)",
      },

      boxShadow: {
        xs: "var(--shadow-xs)",
        sm: "var(--shadow-sm)",
        md: "var(--shadow-md)",
        lg: "var(--shadow-lg)",
        xl: "var(--shadow-xl)",
      },

      transitionDuration: {
        instant: "var(--duration-instant)",
        fast: "var(--duration-fast)",
        base: "var(--duration-base)",
        slow: "var(--duration-slow)",
        slower: "var(--duration-slower)",
      },

      transitionTimingFunction: {
        standard: "var(--ease-standard)",
        decelerate: "var(--ease-decelerate)",
        accelerate: "var(--ease-accelerate)",
      },

      keyframes: {
        "accordion-down": {
          from: { height: "0" },
          to: { height: "rgb(var(--radix-accordion-content-height-rgb) / <alpha-value>)" },
        },
        "accordion-up": {
          from: { height: "rgb(var(--radix-accordion-content-height-rgb) / <alpha-value>)" },
          to: { height: "0" },
        },
      },
      animation: {
        "accordion-down": "accordion-down var(--duration-base) var(--ease-standard)",
        "accordion-up": "accordion-up var(--duration-base) var(--ease-standard)",
      },
    },
  },
  plugins: [animate],
};

export default config;
