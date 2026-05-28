use std::net::TcpListener;

pub fn find_available_port(start: u16) -> u16 {
    (start..start + 100)
        .find(|port| TcpListener::bind(("127.0.0.1", *port)).is_ok())
        .unwrap_or(start)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_find_available_port() {
        let port = find_available_port(8787);
        assert!(port >= 8787 && port < 8887);
    }
}
