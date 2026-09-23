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
        border: "var(--border)",
        input: "var(--input)",
        ring: "var(--ring)",
        background: "var(--background)",
        foreground: "var(--foreground)",
        primary: {
          DEFAULT: "var(--primary)",
          foreground: "var(--primary-foreground)",
        },
        secondary: {
          DEFAULT: "var(--secondary)",
          foreground: "var(--secondary-foreground)",
        },
        destructive: {
          DEFAULT: "var(--destructive)",
          foreground: "var(--destructive-foreground)",
        },
        muted: {
          DEFAULT: "var(--muted)",
          foreground: "var(--muted-foreground)",
        },
        accent: {
          DEFAULT: "var(--accent)",
          foreground: "var(--accent-foreground)",
        },
        card: {
          DEFAULT: "var(--card)",
          foreground: "var(--card-foreground)",
        },
        popover: {
          DEFAULT: "var(--popover)",
          foreground: "var(--popover-foreground)",
        },

        // ---- 2) 新语义层 ----
        brand: {
          DEFAULT: "var(--brand)",
          light: "var(--brand-light)",
          dark: "var(--brand-dark)",
          surface: "var(--brand-surface)",
          foreground: "var(--brand-foreground)",
          accent: "var(--brand-accent)",
          "accent-light": "var(--brand-accent-light)",
          "accent-surface": "var(--brand-accent-surface)",
          "accent-foreground": "var(--brand-accent-foreground)",
        },
        surface: {
          DEFAULT: "var(--surface)",
          card: "var(--surface-card)",
          subtle: "var(--surface-subtle)",
          sunken: "var(--surface-sunken)",
          inverse: "var(--surface-inverse)",
        },
        content: {
          // 命名成 content* 而不是 text*: 避免和 Tailwind 的 text-<size> 撞命名空间
          primary: "var(--text-primary)",
          secondary: "var(--text-secondary)",
          tertiary: "var(--text-tertiary)",
          disabled: "var(--text-disabled)",
          inverse: "var(--text-on-inverse)",
        },
        success: {
          DEFAULT: "var(--success)",
          light: "var(--success-light)",
          surface: "var(--success-surface)",
          foreground: "var(--success-foreground)",
        },
        warning: {
          DEFAULT: "var(--warning)",
          light: "var(--warning-light)",
          surface: "var(--warning-surface)",
          foreground: "var(--warning-foreground)",
        },
        danger: {
          DEFAULT: "var(--danger)",
          light: "var(--danger-light)",
          surface: "var(--danger-surface)",
          foreground: "var(--danger-foreground)",
        },
        info: {
          DEFAULT: "var(--info)",
          light: "var(--info-light)",
          surface: "var(--info-surface)",
          foreground: "var(--info-foreground)",
        },
        divider: "var(--divider)",
        "border-default": "var(--border-default)",
        "border-strong": "var(--border-strong)",
        gold: {
          DEFAULT: "var(--member-gold)",
          surface: "var(--member-gold-surface)",
        },
        neutral: {
          DEFAULT: "var(--badge-neutral)",
          surface: "var(--badge-neutral-surface)",
        },
        graph: {
          a: "var(--graph-a)",
          "a-surface": "var(--graph-a-surface)",
          b: "var(--graph-b)",
          "b-surface": "var(--graph-b-surface)",
          line: "var(--graph-line)",
          "line-soft": "var(--graph-line-soft)",
        },
        scrim: "var(--scrim)",

        // ---- 图表色板 (recharts / 手写 SVG 共用) ----
        chart: {
          1: "var(--chart-1)",
          2: "var(--chart-2)",
          3: "var(--chart-3)",
          4: "var(--chart-4)",
          5: "var(--chart-5)",
          6: "var(--chart-6)",
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

      fontSize: {
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
          to: { height: "var(--radix-accordion-content-height)" },
        },
        "accordion-up": {
          from: { height: "var(--radix-accordion-content-height)" },
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
