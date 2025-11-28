package com.karibu.tech.config;

import com.karibu.tech.security.JwtAuthenticationFilter;
import com.karibu.tech.security.RateLimitingFilter;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.annotation.method.configuration.EnableMethodSecurity;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.annotation.web.configurers.HeadersConfigurer;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;
import org.springframework.security.web.csrf.CookieCsrfTokenRepository;
import org.springframework.security.web.csrf.CsrfTokenRequestAttributeHandler;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

import java.util.Arrays;
import java.util.List;

@Configuration
@EnableWebSecurity
@EnableMethodSecurity
@RequiredArgsConstructor
public class SecurityConfig {

        private final JwtAuthenticationFilter jwtAuthenticationFilter;
        private final RateLimitingFilter rateLimitingFilter;

        @Value("${cors.allowed-origins}")
        private String allowedOrigins;

        @Value("${security.csrf.enabled:true}")
        private boolean csrfEnabled;

        @Bean
        public PasswordEncoder passwordEncoder() {
                // Use BCrypt with strength 14 for maximum security (production-grade)
                return new BCryptPasswordEncoder(14);
        }

        @Bean
        public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
                // CSRF Protection: Enable for production, use cookie-based tokens for SPAs
                if (csrfEnabled) {
                        CsrfTokenRequestAttributeHandler requestHandler = new CsrfTokenRequestAttributeHandler();
                        requestHandler.setCsrfRequestAttributeName("_csrf");

                        http.csrf(csrf -> csrf
                                        .csrfTokenRepository(CookieCsrfTokenRepository.withHttpOnlyFalse())
                                        .csrfTokenRequestHandler(requestHandler)
                                        .ignoringRequestMatchers("/api/v1/auth/login", "/api/v1/auth/register",
                                                        "/api/v1/contact"));
                } else {
                        http.csrf(csrf -> csrf.disable());
                }

                http
                                // CORS Configuration
                                .cors(cors -> cors.configurationSource(corsConfigurationSource()))

                                // Stateless session management (JWT)
                                .sessionManagement(session -> session
                                                .sessionCreationPolicy(SessionCreationPolicy.STATELESS))

                                // Security Headers - CRITICAL for production
                                .headers(headers -> headers
                                                // Content Security Policy - Prevent XSS attacks
                                                .contentSecurityPolicy(csp -> csp.policyDirectives(
                                                                "default-src 'self'; " +
                                                                                "script-src 'self'; " +
                                                                                "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; "
                                                                                +
                                                                                "font-src 'self' https://fonts.gstatic.com; "
                                                                                +
                                                                                "img-src 'self' data: https:; " +
                                                                                "connect-src 'self'; " +
                                                                                "frame-ancestors 'none'; " +
                                                                                "base-uri 'self'; " +
                                                                                "form-action 'self';"))
                                                // HTTP Strict Transport Security - Force HTTPS
                                                .httpStrictTransportSecurity(hsts -> hsts
                                                                .includeSubDomains(true)
                                                                .maxAgeInSeconds(31536000) // 1 year
                                                                .preload(true))
                                                // X-Frame-Options - Prevent clickjacking
                                                .frameOptions(HeadersConfigurer.FrameOptionsConfig::deny)
                                                // X-Content-Type-Options - Prevent MIME sniffing
                                                .contentTypeOptions(HeadersConfigurer.ContentTypeOptionsConfig::disable)
                                                // X-XSS-Protection - Legacy XSS protection
                                                .xssProtection(xss -> xss.headerValue(
                                                                org.springframework.security.web.header.writers.XXssProtectionHeaderWriter.HeaderValue.ENABLED_MODE_BLOCK))
                                                // Referrer Policy
                                                .referrerPolicy(referrer -> referrer.policy(
                                                                org.springframework.security.web.header.writers.ReferrerPolicyHeaderWriter.ReferrerPolicy.STRICT_ORIGIN_WHEN_CROSS_ORIGIN))
                                                // Permissions Policy (formerly Feature Policy)
                                                .permissionsPolicy(permissions -> permissions.policy(
                                                                "geolocation=(), microphone=(), camera=()")))

                                // Authorization rules
                                .authorizeHttpRequests(auth -> auth
                                                // Public endpoints
                                                .requestMatchers("/api/v1/auth/login", "/api/v1/auth/register")
                                                .permitAll()
                                                .requestMatchers("/api/v1/auth/verify-email",
                                                                "/api/v1/auth/resend-verification")
                                                .permitAll()
                                                .requestMatchers("/api/v1/auth/forgot-password",
                                                                "/api/v1/auth/reset-password")
                                                .permitAll()
                                                .requestMatchers("/api/v1/contact").permitAll()
                                                .requestMatchers("/api/v1/functions/**").permitAll()
                                                .requestMatchers("/api/v1/ai/health").permitAll()
                                                .requestMatchers("/actuator/health", "/actuator/info").permitAll()
                                                .requestMatchers("/health", "/").permitAll()
                                                // All other requests require authentication
                                                .anyRequest().authenticated())

                                // JWT Authentication Filter
                                .addFilterBefore(jwtAuthenticationFilter, UsernamePasswordAuthenticationFilter.class)

                                // Rate Limiting Filter (before authentication to prevent brute force)
                                .addFilterBefore(rateLimitingFilter, JwtAuthenticationFilter.class);

                return http.build();
        }

        @Bean
        public CorsConfigurationSource corsConfigurationSource() {
                CorsConfiguration configuration = new CorsConfiguration();

                // SECURITY: Use strict environment-based allowed origins (NO wildcards in
                // production)
                List<String> origins = Arrays.asList(allowedOrigins.split(","));
                configuration.setAllowedOrigins(origins);

                // SECURITY: Restrict allowed methods to only what's needed
                configuration.setAllowedMethods(Arrays.asList("GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"));

                // SECURITY: Explicitly specify allowed headers (DO NOT use wildcard "*" in
                // production)
                configuration.setAllowedHeaders(Arrays.asList(
                                "Authorization",
                                "Content-Type",
                                "Accept",
                                "X-Requested-With",
                                "X-XSRF-TOKEN" // For CSRF protection
                ));

                // SECURITY: Expose only necessary headers to client
                configuration.setExposedHeaders(Arrays.asList(
                                "Authorization",
                                "X-XSRF-TOKEN"));

                // SECURITY: Allow credentials (required for cookies, but MUST NOT be used with
                // wildcard origins)
                configuration.setAllowCredentials(true);

                // Set max age for preflight requests (1 hour)
                configuration.setMaxAge(3600L);

                UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
                source.registerCorsConfiguration("/api/**", configuration);
                return source;
        }
}
