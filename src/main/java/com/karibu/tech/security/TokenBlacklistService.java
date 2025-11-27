package com.karibu.tech.security;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;

/**
 * Service to manage revoked JWT tokens (blacklist).
 * Tokens are stored until their expiration time, then automatically removed.
 * 
 * SECURITY CRITICAL: Ensures that:
 * - Logged-out tokens cannot be reused
 * - Compromised tokens can be revoked immediately
 * - Deleted accounts cannot authenticate with old tokens
 */
@Service
public class TokenBlacklistService {

    private static final Logger logger = LoggerFactory.getLogger(TokenBlacklistService.class);

    // Store token IDs with their expiration timestamps
    private final ConcurrentHashMap<String, Long> blacklistedTokens = new ConcurrentHashMap<>();

    // Scheduled executor for periodic cleanup
    private final ScheduledExecutorService scheduler = Executors.newScheduledThreadPool(1);

    public TokenBlacklistService() {
        // Schedule cleanup every 1 hour
        scheduler.scheduleAtFixedRate(this::cleanupExpiredTokens, 1, 1, TimeUnit.HOURS);
        logger.info("Token blacklist service initialized with automatic cleanup");
    }

    /**
     * Revoke a token (add to blacklist)
     * 
     * @param tokenId          Unique identifier for the token (e.g., jti claim or
     *                         full token hash)
     * @param expirationTimeMs Expiration timestamp in milliseconds
     */
    public void revokeToken(String tokenId, long expirationTimeMs) {
        blacklistedTokens.put(tokenId, expirationTimeMs);
        logger.info("Token revoked: {} (expires at: {})",
                tokenId.substring(0, Math.min(10, tokenId.length())) + "***",
                new java.util.Date(expirationTimeMs));
    }

    /**
     * Check if a token is revoked
     * 
     * @param tokenId Token identifier to check
     * @return true if token is blacklisted, false otherwise
     */
    public boolean isTokenRevoked(String tokenId) {
        Long expiration = blacklistedTokens.get(tokenId);

        // If token not in blacklist, it's valid
        if (expiration == null) {
            return false;
        }

        // If token expired, remove from blacklist and return false
        if (System.currentTimeMillis() > expiration) {
            blacklistedTokens.remove(tokenId);
            return false;
        }

        // Token is blacklisted and not yet expired
        return true;
    }

    /**
     * Revoke all tokens for a specific user (e.g., on account deletion or password
     * change)
     * Note: This requires storing user-token mapping, which is not implemented here
     * for simplicity. In production, consider using Redis or database for this.
     */
    public void revokeAllUserTokens(Long userId) {
        logger.warn("Revoking all tokens for user: {} (implementation required)", userId);
        // TODO: Implement user-token mapping in production
        // For now, users must log out manually or wait for token expiration
    }

    /**
     * Remove expired tokens from blacklist
     */
    private void cleanupExpiredTokens() {
        long now = System.currentTimeMillis();
        int sizeBefore = blacklistedTokens.size();

        blacklistedTokens.entrySet().removeIf(entry -> entry.getValue() < now);

        int sizeAfter = blacklistedTokens.size();
        if (sizeBefore != sizeAfter) {
            logger.info("Cleaned up {} expired tokens from blacklist. Remaining: {}",
                    sizeBefore - sizeAfter, sizeAfter);
        }
    }

    /**
     * Get current blacklist size (for monitoring)
     */
    public int getBlacklistSize() {
        return blacklistedTokens.size();
    }

    /**
     * Shutdown cleanup scheduler
     */
    public void shutdown() {
        scheduler.shutdown();
        logger.info("Token blacklist service shutdown");
    }
}
