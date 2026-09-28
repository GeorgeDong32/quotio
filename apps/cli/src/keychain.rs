//! Serialize legacy macOS Keychain calls so background reads cannot inherit a prompt allowance.
use security_framework::base::{Error, Result};
use security_framework_sys::keychain::{
    SecKeychainGetUserInteractionAllowed, SecKeychainSetUserInteractionAllowed,
};
use std::sync::Mutex;

static INTERACTION: Mutex<()> = Mutex::new(());

#[allow(deprecated)]
pub(crate) fn with_interaction<T>(
    allowed: bool,
    operation: impl FnOnce() -> Result<T>,
) -> Result<T> {
    let _lock = INTERACTION.lock().map_err(|_| Error::from_code(-2070))?;
    let mut previous = 0;
    let status = unsafe { SecKeychainGetUserInteractionAllowed(&mut previous) };
    if status != 0 {
        return Err(Error::from_code(status));
    }
    let status = unsafe { SecKeychainSetUserInteractionAllowed(u8::from(allowed)) };
    if status != 0 {
        return Err(Error::from_code(status));
    }
    struct Restore(u8);
    impl Drop for Restore {
        fn drop(&mut self) {
            unsafe {
                SecKeychainSetUserInteractionAllowed(self.0);
            }
        }
    }
    let _restore = Restore(previous);
    operation()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    #[allow(deprecated)]
    fn background_access_waits_for_authorization_and_cannot_inherit_its_permission() {
        let (started, ready) = std::sync::mpsc::channel();
        let (release, wait) = std::sync::mpsc::channel();
        let interactive = std::thread::spawn(move || {
            with_interaction(true, || {
                let mut allowed = 0;
                assert_eq!(
                    unsafe { SecKeychainGetUserInteractionAllowed(&mut allowed) },
                    0
                );
                assert_eq!(allowed, 1);
                started.send(()).unwrap();
                wait.recv().unwrap();
                Ok(())
            })
        });
        ready.recv().unwrap();
        let background = std::thread::spawn(|| {
            with_interaction(false, || {
                let mut allowed = 1;
                assert_eq!(
                    unsafe { SecKeychainGetUserInteractionAllowed(&mut allowed) },
                    0
                );
                assert_eq!(allowed, 0);
                Ok(())
            })
        });
        release.send(()).unwrap();
        interactive.join().unwrap().unwrap();
        background.join().unwrap().unwrap();
    }
}
