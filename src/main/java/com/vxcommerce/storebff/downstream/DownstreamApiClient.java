package com.vxcommerce.storebff.downstream;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.ParameterizedTypeReference;
import org.springframework.stereotype.Component;
import org.springframework.web.reactive.function.client.WebClient;
import reactor.core.publisher.Mono;

import java.time.Duration;
import java.util.Map;

/**
 * Calls the orders-api API through APIM. infra/ creates an APIM subscription for this
 * service scoped to that API only and passes its key as API_SUBSCRIPTION_KEY, next to API_BASE_URL.
 * Add one method per API operation this service needs.
 */
@Component
public class DownstreamApiClient {

    private static final Duration TIMEOUT = Duration.ofSeconds(10);
    private static final ParameterizedTypeReference<Map<String, Object>> JSON_OBJECT = new ParameterizedTypeReference<>() { };

    private final WebClient webClient;

    @Autowired
    public DownstreamApiClient(@Value("${downstream-api.base-url}") String baseUrl,
                               @Value("${downstream-api.subscription-key}") String subscriptionKey) {
        this(buildClient(baseUrl, subscriptionKey));
    }

    DownstreamApiClient(WebClient webClient) {
        this.webClient = webClient;
    }

    private static WebClient buildClient(String baseUrl, String subscriptionKey) {
        WebClient.Builder builder = WebClient.builder().baseUrl(baseUrl);
        if (!subscriptionKey.isEmpty()) {
            builder.defaultHeader("Ocp-Apim-Subscription-Key", subscriptionKey);
        }
        return builder.build();
    }

    public Mono<Map<String, Object>> health() {
        return webClient.get().uri("/health")
                .retrieve()
                .bodyToMono(JSON_OBJECT)
                .timeout(TIMEOUT);
    }
}
