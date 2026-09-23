//
//  ProviderEnvironment.swift
//  OhMyPi
//
//  Created by Arman Sarvardin on 23/9/26.
//

import Foundation

/// Environment variables each provider reads its API key or token from.
///
/// Generated from `packages/catalog/src/compat/rules.json` (`envVars`); the first
/// entry is the preferred variable. Providers missing here are OAuth-only.
nonisolated enum ProviderEnvironment {
    static let variables: [String: [String]] = [
        "abliteration": ["ABLITERATION_API_KEY", "ABLIT_KEY"],
        "aiand": ["AIAND_API_KEY"],
        "aimlapi": ["AIMLAPI_API_KEY"],
        "alibaba-coding-plan": ["ALIBABA_CODING_PLAN_API_KEY"],
        "alibaba-token-plan": ["ALIBABA_TOKEN_PLAN_API_KEY", "BAILIAN_TOKEN_PLAN_API_KEY"],
        "anthropic": ["ANTHROPIC_API_KEY"],
        "azure": ["AZURE_OPENAI_API_KEY"],
        "baseten": ["BASETEN_API_KEY"],
        "bedrock-mantle": ["AWS_BEARER_TOKEN_BEDROCK"],
        "cerebras": ["CEREBRAS_API_KEY"],
        "charm-hyper": ["CHARM_HYPER_API_KEY", "HYPER_API_KEY"],
        "cline-pass": ["CLINE_API_KEY"],
        "cloudflare-ai-gateway": ["CLOUDFLARE_AI_GATEWAY_API_KEY"],
        "commandcode": ["COMMAND_CODE_API_KEY", "COMMANDCODE_API_KEY"],
        "coreweave": ["COREWEAVE_API_KEY", "WANDB_API_KEY"],
        "cursor": ["CURSOR_ACCESS_TOKEN"],
        "deepinfra": ["DEEPINFRA_API_KEY"],
        "deepseek": ["DEEPSEEK_API_KEY"],
        "devin": ["DEVIN_API_KEY"],
        "discovery": ["CURSOR_API_KEY"],
        "firepass": ["FIREPASS_API_KEY"],
        "fireworks": ["FIREWORKS_API_KEY"],
        "github-copilot": ["COPILOT_GITHUB_TOKEN"],
        "gitlab-duo": ["GITLAB_TOKEN"],
        "gitlab-duo-agent": ["GITLAB_TOKEN"],
        "gmi-cloud": ["GMI_API_KEY"],
        "google": ["GEMINI_API_KEY"],
        "groq": ["GROQ_API_KEY"],
        "huggingface": ["HUGGINGFACE_HUB_TOKEN", "HF_TOKEN"],
        "kilo": ["KILO_API_KEY"],
        "litellm": ["LITELLM_API_KEY"],
        "lm-studio": ["LM_STUDIO_API_KEY"],
        "meta": ["MODEL_API_KEY", "META_API_KEY"],
        "minimax": ["MINIMAX_API_KEY"],
        "minimax-code": ["MINIMAX_CODE_API_KEY"],
        "minimax-code-cn": ["MINIMAX_CODE_CN_API_KEY"],
        "mistral": ["MISTRAL_API_KEY"],
        "moonshot": ["MOONSHOT_API_KEY", "KIMI_API_KEY"],
        "nanogpt": ["NANO_GPT_API_KEY"],
        "novita": ["NOVITA_API_KEY"],
        "nvidia": ["NVIDIA_API_KEY"],
        "ollama": ["OLLAMA_API_KEY"],
        "ollama-cloud": ["OLLAMA_CLOUD_API_KEY"],
        "openai": ["OPENAI_API_KEY"],
        "openai-codex": ["OPENAI_CODEX_OAUTH_TOKEN"],
        "opencode-go": ["OPENCODE_API_KEY"],
        "opencode-zen": ["OPENCODE_API_KEY"],
        "openrouter": ["OPENROUTER_API_KEY"],
        "qianfan": ["QIANFAN_API_KEY"],
        "qwen-portal": ["QWEN_OAUTH_TOKEN", "QWEN_PORTAL_API_KEY"],
        "sakana": ["SAKANA_API_KEY", "FUGU_API_KEY"],
        "siliconflow": ["SILICONFLOW_API_KEY"],
        "siliconflow-cn": ["SILICONFLOW_CN_API_KEY"],
        "singularityapi": ["SINGULARITYAPI_API_KEY"],
        "synthetic": ["SYNTHETIC_API_KEY"],
        "together": ["TOGETHER_API_KEY"],
        "typesafe": ["TYPESAFE_API_KEY"],
        "umans": ["UMANS_AI_CODING_PLAN_API_KEY"],
        "venice": ["VENICE_API_KEY"],
        "vercel-ai-gateway": ["AI_GATEWAY_API_KEY"],
        "vllm": ["VLLM_API_KEY"],
        "wafer-serverless": ["WAFER_SERVERLESS_API_KEY"],
        "xai": ["XAI_API_KEY"],
        "xai-oauth": ["XAI_OAUTH_TOKEN", "XAI_API_KEY"],
        "xiaomi": ["XIAOMI_API_KEY"],
        "xiaomi-token-plan-ams": ["XIAOMI_TOKEN_PLAN_AMS_API_KEY"],
        "xiaomi-token-plan-cn": ["XIAOMI_TOKEN_PLAN_CN_API_KEY"],
        "xiaomi-token-plan-sgp": ["XIAOMI_TOKEN_PLAN_SGP_API_KEY"],
        "yolo-auto": ["YOLO_AUTO_API_KEY"],
        "zai": ["ZAI_API_KEY"],
        "zenmux": ["ZENMUX_API_KEY"],
        "zhipu-coding-plan": ["ZHIPU_API_KEY"]
    ]

    static func variables(for providerId: String) -> [String] {
        variables[providerId] ?? []
    }

    /// Tokens obtained through an OAuth flow rather than pasted API keys.
    static func isOAuthVariable(_ name: String) -> Bool {
        name.hasSuffix("_OAUTH_TOKEN") || name.hasSuffix("_ACCESS_TOKEN") || name == "GITLAB_TOKEN" || name == "COPILOT_GITHUB_TOKEN"
    }
}
