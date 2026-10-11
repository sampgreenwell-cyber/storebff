package com.vxcommerce.storebff;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;

import java.util.Map;

/**
 * Health endpoint used by the Container App startup, readiness and liveness probes
 * (infra/main.bicep sets healthPath to /health). Keep it dependency-free: a probe that
 * calls downstream services restarts this app whenever they are slow.
 */
@RestController
public class HealthController {

    private final String serviceName;

    public HealthController(@Value("${spring.application.name}") String serviceName) {
        this.serviceName = serviceName;
    }

    @GetMapping("/health")
    public Mono<Map<String, String>> health() {
        return Mono.just(Map.of(
                "status", "ok",
                "service", serviceName
        ));
    }
}
