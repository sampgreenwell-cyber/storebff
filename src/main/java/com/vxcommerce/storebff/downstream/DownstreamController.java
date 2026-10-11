package com.vxcommerce.storebff.downstream;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;

import java.util.Map;

/**
 * Proves the whole chain: caller -> APIM -> this service -> APIM -> orders-api.
 * Deliberately not part of /health, so a slow API never fails this service's probes.
 */
@RestController
public class DownstreamController {

    private final DownstreamApiClient api;
    private final String serviceName;

    public DownstreamController(DownstreamApiClient api, @Value("${spring.application.name}") String serviceName) {
        this.api = api;
        this.serviceName = serviceName;
    }

    @GetMapping("/downstream/health")
    public Mono<ResponseEntity<Map<String, Object>>> health() {
        return api.health()
                .map(apiHealth -> ResponseEntity.ok(Map.<String, Object>of("service", serviceName, "api", apiHealth)))
                .onErrorResume(error -> Mono.just(ResponseEntity.status(HttpStatus.BAD_GATEWAY)
                        .body(Map.of("service", serviceName, "error", "The orders-api API did not answer: " + error.getClass().getSimpleName()))));
    }
}
