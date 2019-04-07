<?php
$respData = array();

if (isset($_GET['code']) && !empty($_GET['code'])) {
    $oauth2_code = trim($_GET['code']);
    $respData = array('oauth2_code' => $oauth2_code);

    http_response_code(200);
    header('Content-Type: application/json');
    header('Content-Disposition: attachment; filename=authorization.json');
    header('Pragma: no-cache');
    echo json_encode($respData);
}
else {
    http_response_code(400);
}
?>
