import type { PluginInput } from "@opencode-ai/plugin";
import type {
  NotificationBackend,
  NotificationContext,
  NotificationEvent,
} from "opencode-notification-sdk";
import { renderTemplate, execTemplate } from "opencode-notification-sdk";
import { request as httpsRequest } from "node:https";
import type {
  NtfyBackendConfig,
  ContentTemplate,
  ContentTemplateMap,
} from "./config.js";

const DEFAULT_TITLES: Record<NotificationEvent, string> = {
  "session.idle": "Agent Idle",
  "session.error": "Agent Error",
  "permission.asked": "Permission Asked",
};

const DEFAULT_MESSAGES: Record<NotificationEvent, string> = {
  "session.idle": "The agent has finished and is waiting for input.",
  "session.error": "An error has occurred. Check the session for details.",
  "permission.asked":
    "The agent needs permission to continue. Review and respond.",
};

const DEFAULT_TAGS: Record<NotificationEvent, string> = {
  "session.idle": "hourglass_done",
  "session.error": "warning",
  "permission.asked": "lock",
};

function isValueTemplate(
  template: ContentTemplate
): template is { readonly value: string } {
  return "value" in template;
}

async function resolveContent(
  templateMap: ContentTemplateMap | undefined,
  event: NotificationEvent,
  defaults: Record<NotificationEvent, string>,
  context: NotificationContext,
  $?: PluginInput["$"]
): Promise<string> {
  const template = templateMap?.[event];
  if (!template) {
    return defaults[event] ?? "";
  }
  if (isValueTemplate(template)) {
    return renderTemplate(template.value, context);
  }
  // command template
  if (!$) {
    throw new Error(
      `Command template configured for ${event} but no shell ($) was provided`
    );
  }
  return execTemplate($, template.command, context);
}

export function createNtfyBackend(
  config: NtfyBackendConfig,
  $?: PluginInput["$"]
): NotificationBackend {
  return {
    async send(context: NotificationContext): Promise<void> {
      const url = `${config.server.replace(/\/+$/, "")}/${config.topic}`;

      const title = await resolveContent(
        config.title,
        context.event,
        DEFAULT_TITLES,
        context,
        $
      );
      const message = await resolveContent(
        config.message,
        context.event,
        DEFAULT_MESSAGES,
        context,
        $
      );
      const tags = DEFAULT_TAGS[context.event] ?? "";

      const headers: Record<string, string> = {
        Title: title,
        Priority: config.priority,
        Tags: tags,
        "X-Icon": config.iconUrl,
        ...(config.token
          ? { Authorization: `Bearer ${config.token}` }
          : {}),
      };

      if (config.allowInsecure) {
        // Node.js fetch() ignores the dispatcher option, so we must use
        // https.request directly when TLS verification needs to be disabled.
        await sendViaHttps(url, headers, message, config.fetchTimeout);
      } else {
        const fetchOptions: RequestInit = {
          method: "POST",
          headers,
          body: message,
          ...(config.fetchTimeout !== undefined
            ? { signal: AbortSignal.timeout(config.fetchTimeout) }
            : {}),
        };

        const response = await fetch(url, fetchOptions);

        if (!response.ok) {
          throw new Error(
            `ntfy request failed: ${response.status} ${response.statusText}`
          );
        }
      }
    },
  };
}

function sendViaHttps(
  url: string,
  headers: Record<string, string>,
  body: string,
  timeoutMs?: number
): Promise<void> {
  return new Promise((resolve, reject) => {
    const parsed = new URL(url);
    const req = httpsRequest(
      {
        hostname: parsed.hostname,
        port: parsed.port ? parseInt(parsed.port, 10) : 443,
        path: parsed.pathname,
        method: "POST",
        headers,
        rejectUnauthorized: false,
        timeout: timeoutMs,
      },
      (res) => {
        if (res.statusCode !== undefined && res.statusCode >= 200 && res.statusCode < 300) {
          resolve();
        } else {
          reject(
            new Error(
              `ntfy request failed: ${res.statusCode ?? "unknown"} ${res.statusMessage ?? ""}`
            )
          );
        }
      }
    );

    req.on("error", reject);
    req.on("timeout", () => {
      req.destroy();
      reject(new Error("ntfy request timed out"));
    });

    req.write(body);
    req.end();
  });
}
