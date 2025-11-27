package com.karibu.tech.security;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.TimeUnit;

/**
 * Rate limiting filter to prevent brute force attacks and API abuse.
 * Tracks requests per IP address and blocks excessive requests.
 * 
 * SECURITY CRITICAL: This protects against:
 * - Brute force login attempts
 * - DDoS attacks
 * - API abuse
 * - Account enumeration
 */
@Component
public class RateLimitingFilter extends OncePerRequestFilter {

    private static final Logger logger = LoggerFactory.getLogger(RateLimitingFilter.class);

    // Track request counts per IP
    private final ConcurrentHashMap<String, RequestCounter> requestCounts = new ConcurrentHashMap<>();

    // Rate limits configuration
    private static final int MAX_REQUESTS_PER_MINUTE = 60;
    private static final int MAX_AUTH_REQUESTS_PER_MINUTE = 5; // Stricter for auth endpoints
    private static final long CLEANUP_INTERVAL_MS = TimeUnit.MINUTES.toMillis(5);

    private long lastCleanup = System.currentTimeMillis();

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain filterChain)
            throws ServletException, IOException {

        String clientIP = getClientIP(request);
        String requestURI = request.getRequestURI();

        // Determine rate limit based on endpoint
        int maxRequests = isAuthEndpoint(requestURI) ? MAX_AUTH_REQUESTS_PER_MINUTE : MAX_REQUESTS_PER_MINUTE;

        // Check rate limit
        if (isRateLimited(clientIP, maxRequests)) {
            logger.warn("Rate limit exceeded for IP: {} on endpoint: {}", clientIP, requestURI);
            response.setStatus(429); // 429 Too Many Requests
            response.setContentType("application/json");
            response.getWriter().write(
                    "{\"status\":\"error\",\"message\":\"Zu viele Anfragen. Bitte versuchen Sie es später erneut.\"}");
            return;
        }

        // Periodic cleanup of old entries
        cleanupIfNeeded();

        filterChain.doFilter(request, response);
    }

    private boolean isAuthEndpoint(String uri) {
        return uri.contains("/auth/login") ||
                uri.contains("/auth/register") ||
                uri.contains("/auth/reset-password");
    }

    private boolean isRateLimited(String clientIP, int maxRequests) {
        RequestCounter counter = requestCounts.computeIfAbsent(clientIP, k -> new RequestCounter());
        return !counter.allowRequest(maxRequests);
    }

    private String getClientIP(HttpServletRequest request) {
        // Check for proxy headers (X-Forwarded-For, X-Real-IP)
        String ip = request.getHeader("X-Forwarded-For");
        if (ip == null || ip.isEmpty() || "unknown".equalsIgnoreCase(ip)) {
            ip = request.getHeader("X-Real-IP");
        }
        if (ip == null || ip.isEmpty() || "unknown".equalsIgnoreCase(ip)) {
            ip = request.getRemoteAddr();
        }
        // If multiple IPs in X-Forwarded-For, take the first one
        if (ip != null && ip.contains(",")) {
            ip = ip.split(",")[0].trim();
        }
        return ip;
    }

    private void cleanupIfNeeded() {
        long now = System.currentTimeMillis();
        if (now - lastCleanup > CLEANUP_INTERVAL_MS) {
            requestCounts.entrySet().removeIf(entry -> entry.getValue().isExpired());
            lastCleanup = now;
            logger.debug("Cleaned up expired rate limit entries. Current size: {}", requestCounts.size());
        }
    }

    /**
     * Internal class to track request counts with sliding window
     */
    private static class RequestCounter {
        private static final long WINDOW_SIZE_MS = TimeUnit.MINUTES.toMillis(1);
        private long windowStart;
        private int count;

        public RequestCounter() {
            this.windowStart = System.currentTimeMillis();
            this.count = 0;
        }

        public synchronized boolean allowRequest(int maxRequests) {
            long now = System.currentTimeMillis();

            // Reset counter if window has passed
            if (now - windowStart > WINDOW_SIZE_MS) {
                windowStart = now;
                count = 0;
            }

            // Check if limit exceeded
            if (count >= maxRequests) {
                return false;
            }

            count++;
            return true;
        }

        public boolean isExpired() {
            return System.currentTimeMillis() - windowStart > WINDOW_SIZE_MS * 2;
        }
    }
}
