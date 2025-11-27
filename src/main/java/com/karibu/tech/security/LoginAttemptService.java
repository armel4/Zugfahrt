package com.karibu.tech.security;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Service to track failed login attempts and implement account lockout.
 * 
 * SECURITY CRITICAL: Prevents brute force attacks by:
 * - Tracking failed login attempts per email
 * - Temporarily locking accounts after too many failures
 * - Logging all suspicious activity
 */
@Service
public class LoginAttemptService {

    private static final Logger logger = LoggerFactory.getLogger(LoginAttemptService.class);

    private static final int MAX_ATTEMPTS = 5;
    private static final int LOCKOUT_DURATION_MINUTES = 15;

    private final ConcurrentHashMap<String, AttemptInfo> attemptsCache = new ConcurrentHashMap<>();

    /**
     * Record a successful login - clears failed attempts
     */
    public void loginSucceeded(String email) {
        attemptsCache.remove(email);
        logger.info("Successful login for email: {}", maskEmail(email));
    }

    /**
     * Record a failed login attempt
     */
    public void loginFailed(String email) {
        AttemptInfo info = attemptsCache.computeIfAbsent(email, k -> new AttemptInfo());
        info.incrementAttempts();

        if (info.getAttempts() >= MAX_ATTEMPTS) {
            logger.warn("Account locked due to too many failed attempts: {}", maskEmail(email));
        } else {
            logger.warn("Failed login attempt for email: {}. Attempts: {}/{}",
                    maskEmail(email), info.getAttempts(), MAX_ATTEMPTS);
        }
    }

    /**
     * Check if an account is currently locked
     */
    public boolean isLocked(String email) {
        AttemptInfo info = attemptsCache.get(email);
        if (info == null) {
            return false;
        }

        // Check if lockout period has expired
        if (info.isLockedOut()) {
            if (info.getLockoutTime().plusMinutes(LOCKOUT_DURATION_MINUTES).isBefore(LocalDateTime.now())) {
                // Lockout expired, remove from cache
                attemptsCache.remove(email);
                logger.info("Account lockout expired for: {}", maskEmail(email));
                return false;
            }
            return true;
        }

        return false;
    }

    /**
     * Get remaining lockout time in minutes
     */
    public int getRemainingLockoutMinutes(String email) {
        AttemptInfo info = attemptsCache.get(email);
        if (info == null || !info.isLockedOut()) {
            return 0;
        }

        LocalDateTime unlockTime = info.getLockoutTime().plusMinutes(LOCKOUT_DURATION_MINUTES);
        long remainingMinutes = java.time.Duration.between(LocalDateTime.now(), unlockTime).toMinutes();
        return (int) Math.max(0, remainingMinutes);
    }

    /**
     * Mask email for security logging (show only first 3 chars + domain)
     * Example: john.doe@example.com -> joh***@example.com
     */
    private String maskEmail(String email) {
        if (email == null || email.length() < 3) {
            return "***";
        }
        int atIndex = email.indexOf('@');
        if (atIndex <= 0) {
            return email.substring(0, 3) + "***";
        }
        String local = email.substring(0, atIndex);
        String domain = email.substring(atIndex);
        String masked = local.length() > 3 ? local.substring(0, 3) + "***" : local;
        return masked + domain;
    }

    /**
     * Internal class to track attempt information
     */
    private static class AttemptInfo {
        private int attempts;
        private LocalDateTime lockoutTime;

        public AttemptInfo() {
            this.attempts = 0;
            this.lockoutTime = null;
        }

        public void incrementAttempts() {
            attempts++;
            if (attempts >= MAX_ATTEMPTS && lockoutTime == null) {
                lockoutTime = LocalDateTime.now();
            }
        }

        public int getAttempts() {
            return attempts;
        }

        public boolean isLockedOut() {
            return lockoutTime != null;
        }

        public LocalDateTime getLockoutTime() {
            return lockoutTime;
        }
    }
}
