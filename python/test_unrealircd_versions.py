#!/usr/bin/env python3
"""
Unit tests for unrealircd-versions.py
"""

import unittest
from unittest.mock import patch, MagicMock
import sys
import os

# Import the script module
import importlib.util
spec = importlib.util.spec_from_file_location(
    "unrealircd_versions",
    os.path.join(os.path.dirname(__file__), "unrealircd-versions.py")
)
unrealircd_versions = importlib.util.module_from_spec(spec)
sys.modules["unrealircd_versions"] = unrealircd_versions
spec.loader.exec_module(unrealircd_versions)


class TestVersionTuple(unittest.TestCase):
    """Test version_tuple function"""

    def test_simple_version(self):
        """Test parsing simple version strings"""
        self.assertEqual(
            unrealircd_versions.version_tuple("6.0.0"),
            (6, 0, 0)
        )

    def test_two_part_version(self):
        """Test parsing two-part version strings"""
        self.assertEqual(
            unrealircd_versions.version_tuple("5.4"),
            (5, 4)
        )

    def test_version_comparison(self):
        """Test that version tuples compare correctly"""
        v1 = unrealircd_versions.version_tuple("6.0.1")
        v2 = unrealircd_versions.version_tuple("6.0.0")
        self.assertGreater(v1, v2)

    def test_version_comparison_minor(self):
        """Test that minor version differences are detected"""
        v1 = unrealircd_versions.version_tuple("6.1.0")
        v2 = unrealircd_versions.version_tuple("6.0.0")
        self.assertGreater(v1, v2)


class TestIRCBasics(unittest.TestCase):
    """Test IRC class basic functionality"""

    @patch('socket.create_connection')
    def test_irc_init_unencrypted(self, mock_socket):
        """Test IRC initialization with unencrypted connection"""
        mock_sock = MagicMock()
        mock_socket.return_value = mock_sock

        irc = unrealircd_versions.IRC("test.example.com", 6667)

        mock_socket.assert_called_once_with(
            ("test.example.com", 6667),
            timeout=15
        )
        self.assertEqual(irc.sock, mock_sock)

    @patch('socket.create_connection')
    @patch('ssl.create_default_context')
    def test_irc_init_encrypted(self, mock_ssl_ctx, mock_socket):
        """Test IRC initialization with SSL connection"""
        mock_raw = MagicMock()
        mock_socket.return_value = mock_raw
        mock_ctx = MagicMock()
        mock_ssl_ctx.return_value = mock_ctx
        mock_wrapped = MagicMock()
        mock_ctx.wrap_socket.return_value = mock_wrapped

        irc = unrealircd_versions.IRC("test.example.com", 6697)

        mock_socket.assert_called_once()
        mock_ctx.wrap_socket.assert_called_once()
        self.assertEqual(irc.sock, mock_wrapped)

    @patch('socket.create_connection')
    def test_irc_send(self, mock_socket):
        """Test IRC send method"""
        mock_sock = MagicMock()
        mock_socket.return_value = mock_sock

        irc = unrealircd_versions.IRC("test.example.com", 6667)
        
        with patch('builtins.print'):
            irc.send("PRIVMSG #channel :Hello")

        mock_sock.sendall.assert_called_once_with(
            b"PRIVMSG #channel :Hello\r\n"
        )

    @patch('socket.create_connection')
    def test_irc_close(self, mock_socket):
        """Test IRC close method"""
        mock_sock = MagicMock()
        mock_socket.return_value = mock_sock

        irc = unrealircd_versions.IRC("test.example.com", 6667)
        irc.close()

        mock_sock.close.assert_called_once()


class TestGetServerVersion(unittest.TestCase):
    """Test version extraction from IRC responses"""

    @patch('socket.create_connection')
    def test_extract_version_from_response(self, mock_socket):
        """Test extracting version from VERSION command response"""
        mock_sock = MagicMock()
        mock_socket.return_value = mock_sock

        irc = unrealircd_versions.IRC("test.example.com", 6667)
        
        # Mock the receive method to return a VERSION response
        irc.receive = MagicMock(
            return_value=":test.server 351 nick server UnrealIRCd-6.0.3 :info"
        )

        with patch('builtins.print'):
            version = unrealircd_versions.get_server_version(irc, "test.server")

        self.assertEqual(version, "6.0.3")

    @patch('socket.create_connection')
    def test_version_not_found(self, mock_socket):
        """Test handling when version command returns error"""
        mock_sock = MagicMock()
        mock_socket.return_value = mock_sock

        irc = unrealircd_versions.IRC("test.example.com", 6667)
        
        # Mock error response
        irc.receive = MagicMock(
            return_value=":test.server 402 nick test.server :No such server"
        )

        with patch('builtins.print'):
            version = unrealircd_versions.get_server_version(irc, "test.server")

        self.assertIsNone(version)


if __name__ == '__main__':
    unittest.main()
